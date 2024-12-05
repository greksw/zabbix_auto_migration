#!/bin/bash

# Параметры для старого и нового серверов
OLD_SERVER_IP="old-server-ip"
OLD_SERVER_USER="old-server-user"
DB_NAME="zabbix_db_name"
DB_USER="zabbix_db_user"
DB_PASSWORD="zabbix_db_password"
NEW_SERVER_IP="localhost"  # Установим на новый сервер
NEW_ZABBIX_DB_NAME="zabbix_db_name"
NEW_ZABBIX_DB_USER="zabbix_db_user"
NEW_ZABBIX_DB_PASSWORD="zabbix_db_password"
NGINX_CERT_DIR="/etc/ssl/certs/zabbix"  # Директория для сертификатов

# Установим Zabbix, MySQL и Nginx на новом сервере
echo "Installing Zabbix, MySQL, and Nginx on the new server..."
dnf update -y
dnf install -y mysql-server nginx zabbix-server-mysql zabbix-web-mysql zabbix-agent

# Установим и настроим MySQL
echo "Setting up MySQL..."
systemctl start mysql
systemctl enable mysql
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

# Настройка Nginx для Zabbix
echo "Configuring Nginx for Zabbix..."
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
cat <<EOF > /etc/nginx/conf.d/zabbix.conf
server {
    listen 80;
    server_name yourdomain.com;
    
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

# Устанавливаем SSL сертификаты для HTTPS
echo "Setting up SSL certificates for HTTPS..."
mkdir -p $NGINX_CERT_DIR
# Здесь предполагаем, что сертификаты уже существуют или вы используете Let's Encrypt
# Команды для установки сертификатов Let's Encrypt (если они ещё не установлены):
# dnf install -y certbot
# certbot --nginx -d yourdomain.com

# Настроим Nginx на работу с HTTPS
cat <<EOF > /etc/nginx/conf.d/zabbix_https.conf
server {
    listen 443 ssl;
    server_name yourdomain.com;
    ssl_certificate $NGINX_CERT_DIR/fullchain.pem;
    ssl_certificate_key $NGINX_CERT_DIR/privkey.pem;

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

# Перезапуск Nginx и MySQL
echo "Starting services..."
systemctl restart nginx
systemctl restart zabbix-server
systemctl restart zabbix-agent

# Завершаем настройку и тестируем
echo "Testing Zabbix installation on the new server..."
systemctl status nginx
systemctl status zabbix-server

echo "Migration complete! You can access Zabbix via https://yourdomain.com."
