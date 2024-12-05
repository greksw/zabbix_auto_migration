#!/bin/bash

# Устанавливаем необходимые пакеты
echo "Installing required packages..."
dnf install -y openssl nginx

# Настроим директории для сертификатов
CERT_DIR="/etc/ssl"
PRIVATE_KEY_DIR="$CERT_DIR/private"
CERT_DIR="$CERT_DIR/certs"
mkdir -p $PRIVATE_KEY_DIR $CERT_DIR

# Создадим приватный ключ
echo "Creating private key..."
openssl genpkey -algorithm RSA -out $PRIVATE_KEY_DIR/zabbix.key -aes256

# Создадим запрос на сертификат (CSR)
echo "Creating certificate signing request (CSR)..."
openssl req -new -key $PRIVATE_KEY_DIR/zabbix.key -out $PRIVATE_KEY_DIR/zabbix.csr -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=yourdomain.com/emailAddress=youremail@example.com"

# Создадим самоподписной сертификат
echo "Creating self-signed certificate..."
openssl x509 -req -days 365 -in $PRIVATE_KEY_DIR/zabbix.csr -signkey $PRIVATE_KEY_DIR/zabbix.key -out $CERT_DIR/zabbix.crt

# Настроим Nginx для использования SSL
echo "Configuring Nginx to use SSL..."
NGINX_CONF="/etc/nginx/conf.d/zabbix_https.conf"
cat <<EOF > $NGINX_CONF
server {
    listen 443 ssl;
    server_name yourdomain.com;  # Замените на ваш домен или IP-адрес

    ssl_certificate $CERT_DIR/zabbix.crt;
    ssl_certificate_key $PRIVATE_KEY_DIR/zabbix.key;

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

# Перезапустим Nginx, чтобы применить изменения
echo "Restarting Nginx..."
systemctl restart nginx

# Проверим статус Nginx
echo "Checking Nginx status..."
systemctl status nginx

echo "Self-signed SSL certificate created and Nginx configured."
echo "You can access Zabbix via https://yourdomain.com."
