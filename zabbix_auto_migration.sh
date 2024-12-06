#!/bin/bash

# Параметры для старого и нового серверов
OLD_SERVER_IP="192.168.2.31"  # IP старого сервера
OLD_SERVER_USER="old-server-user"
DB_NAME="zabbix_db_name"
DB_USER="zabbix_db_user"
DB_PASSWORD="zabbix_db_password"
NEW_SERVER_IP="192.168.2.30"  # IP нового сервера
NEW_ZABBIX_DB_NAME="zabbix_db_name"
NEW_ZABBIX_DB_USER="zabbix_db_user"
NEW_ZABBIX_DB_PASSWORD="zabbix_db_password"
NGINX_CERT_DIR="/etc/ssl/certs/zabbix"  # Директория для сертификатов
NGINX_PRIVATE_KEY_DIR="/etc/ssl/private"


echo "[epel] >> " >>  /etc/yum.repos.d/epel.repo
echo "excludepkgs=zabbix*" >> /etc/yum.repos.d/epel.repo

#Загрузка репозитория zabbix 7 для Almalinux
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
dnf clean all
dnf makecache

# Устанавливаем Zabbix, MySQL и Nginx на новом сервере
echo "Installing Zabbix, MySQL, and Nginx on the new server..."
dnf update -y
dnf install -y mariadb-server
dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent

#Установка локалей
sudo dnf install -y glibc-langpack-en glibc-langpack-ru

# Установим и настроим MySQL
echo "Setting up MySQL..."
systemctl start mariadb
systemctl enable mariadb
mysql_secure_installation

# Создадим базу данных на новом сервере
echo "Creating Zabbix database on the new server..."
mysql -u root -e "CREATE DATABASE $NEW_ZABBIX_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
mysql -u root -e "CREATE USER '$NEW_ZABBIX_DB_USER'@'localhost' IDENTIFIED BY '$NEW_ZABBIX_DB_PASSWORD';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $NEW_ZABBIX_DB_NAME.* TO '$NEW_ZABBIX_DB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Экспорт базы данных Zabbix с исходного сервера
echo "Exporting Zabbix database from the old server..."
ssh $OLD_SERVER_USER@$OLD_SERVER_IP "mysqldump -u $DB_USER -p$DB_PASSWORD $DB_NAME > /tmp/zabbix_backup.sql"

# Переносим дамп на новый сервер
echo "Transferring the Zabbix database dump to the new server..."
scp $OLD_SERVER_USER@$OLD_SERVER_IP:/tmp/zabbix_backup.sql /tmp/zabbix_backup.sql

# Импортируем базу данных на новом сервере
echo "Importing the Zabbix database on the new server..."
mysql -u root $NEW_ZABBIX_DB_NAME < /tmp/zabbix_backup.sql

# Настройка конфигурации Zabbix
echo "Configuring Zabbix server configuration on the new server..."
sed -i "s/^# DBPassword=.*/DBPassword=$NEW_ZABBIX_DB_PASSWORD/" /etc/zabbix/zabbix_server.conf

# Настройка веб-конфигурации Zabbix (zabbix.conf.php)
echo "Configuring Zabbix web interface..."
cp /etc/zabbix/web/zabbix.conf.php /etc/zabbix/web/zabbix.conf.php.orig
sed -i "s/^.*DBPassword.*$/    \$DB['PASSWORD'] = '$NEW_ZABBIX_DB_PASSWORD';/" /etc/zabbix/web/zabbix.conf.php

# Установка самоподписного сертификата
echo "Creating self-signed SSL certificate..."

# Создадим директории для сертификатов
mkdir -p $NGINX_CERT_DIR
mkdir -p $NGINX_PRIVATE_KEY_DIR

# Создадим приватный ключ
openssl genpkey -algorithm RSA -out $NGINX_PRIVATE_KEY_DIR/zabbix.key -aes256

# Создадим запрос на сертификат (CSR)
openssl req -new -key $NGINX_PRIVATE_KEY_DIR/zabbix.key -out $NGINX_PRIVATE_KEY_DIR/zabbix.csr -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=yourdomain.com/emailAddress=youremail@example.com"

# Создадим самоподписной сертификат
openssl x509 -req -days 365 -in $NGINX_PRIVATE_KEY_DIR/zabbix.csr -signkey $NGINX_PRIVATE_KEY_DIR/zabbix.key -out $NGINX_CERT_DIR/zabbix.crt

# Настроим Nginx для использования SSL
echo "Configuring Nginx for SSL..."
NGINX_CONF="/etc/nginx/conf.d/zabbix_https.conf"
cat <<EOF > $NGINX_CONF
server {
    listen 443 ssl;
    server_name yourdomain.com;  # Замените на ваш домен или IP-адрес

    ssl_certificate $NGINX_CERT_DIR/zabbix.crt;
    ssl_certificate_key $NGINX_PRIVATE_KEY_DIR/zabbix.key;

    location / {
        root /usr/share/zabbix;
        index index.php;
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /usr/share/zabbix/\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# Разрешение сетевых соединений для Nginx
# SELinux может блокировать сетевые подключения для Nginx. Выполните команды для разрешения:
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_connect_db 1

#Открытие портов в файрволе
#Открытие 443 порта
sudo firewall-cmd --add-service=https --permanent
sudo firewall-cmd --reload

# Перезапустим Nginx, чтобы применить изменения
echo "Restarting Nginx..."
systemctl restart nginx

# Перезапуск Zabbix
echo "Restarting Zabbix server..."
systemctl restart zabbix-server
systemctl restart zabbix-agent

# Завершаем настройку и тестируем
echo "Testing Zabbix installation on the new server..."
systemctl status nginx
systemctl status zabbix-server

echo "Migration complete! You can access Zabbix via https://yourdomain.com."
