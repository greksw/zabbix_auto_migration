#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
CONFIG_FILE=${1:-/etc/zabbix-migration.conf}

main() {
    load_config "${CONFIG_FILE}"
    require_command systemctl
    require_command curl

    local service
    for service in mariadb zabbix-server zabbix-agent php-fpm nginx; do
        systemctl is-active --quiet "${service}" || fatal "Service is not active: ${service}"
        log "Service active: ${service}"
    done

    local scheme=https
    [[ -r ${TLS_CERT_FILE} ]] || scheme=http

    curl --fail --silent --show-error --insecure \
        --resolve "${ZABBIX_SERVER_NAME}:443:127.0.0.1" \
        "${scheme}://${ZABBIX_SERVER_NAME}/" >/dev/null \
        || fatal 'Zabbix frontend HTTP(S) validation failed.'

    log 'Post-migration validation completed successfully.'
}

main "$@"
