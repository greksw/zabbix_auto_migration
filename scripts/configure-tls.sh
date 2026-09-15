#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
CONFIG_FILE=${1:-/etc/zabbix-migration.conf}

main() {
    require_root
    load_config "${CONFIG_FILE}"
    require_command nginx
    require_command openssl

    if [[ ${TLS_MODE} == self-signed ]]; then
        install -d -m 0755 "$(dirname "${TLS_CERT_FILE}")"
        install -d -m 0700 "$(dirname "${TLS_KEY_FILE}")"
        log "Generating self-signed certificate for ${ZABBIX_SERVER_NAME}."
        openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
            -days "${SELF_SIGNED_DAYS}" \
            -subj "/CN=${ZABBIX_SERVER_NAME}" \
            -addext "subjectAltName=DNS:${ZABBIX_SERVER_NAME}" \
            -keyout "${TLS_KEY_FILE}" \
            -out "${TLS_CERT_FILE}"
        chmod 0600 "${TLS_KEY_FILE}"
        chmod 0644 "${TLS_CERT_FILE}"
    else
        [[ -r ${TLS_CERT_FILE} ]] || fatal "Certificate not readable: ${TLS_CERT_FILE}"
        [[ -r ${TLS_KEY_FILE} ]] || fatal "Private key not readable: ${TLS_KEY_FILE}"
    fi

    cat > /etc/nginx/conf.d/zabbix-migration-https.conf <<EOF
server {
    listen 443 ssl;
    server_name ${ZABBIX_SERVER_NAME};

    ssl_certificate ${TLS_CERT_FILE};
    ssl_certificate_key ${TLS_KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;

    root /usr/share/zabbix;
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/zabbix.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

    nginx -t
    systemctl enable --now php-fpm nginx
    systemctl reload nginx
    log 'TLS frontend configuration completed.'
}

main "$@"
