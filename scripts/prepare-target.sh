#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
CONFIG_FILE="${1:-/etc/zabbix-migration.conf}"

main() {
    require_root
    load_config "${CONFIG_FILE}"
    require_almalinux_9
    require_command dnf
    require_command rpm

    local release_rpm
    release_rpm="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/9/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el9.noarch.rpm"

    log "Configuring Zabbix ${ZABBIX_VERSION} repository."
    rpm -Uvh --replacepkgs "${release_rpm}"
    dnf clean all

    log 'Installing Zabbix server/frontend, MariaDB and nginx packages.'
    dnf install -y \
        mariadb-server nginx \
        zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf \
        zabbix-sql-scripts zabbix-selinux-policy zabbix-agent \
        glibc-langpack-en glibc-langpack-ru

    systemctl enable --now mariadb
    systemctl enable zabbix-server zabbix-agent nginx php-fpm

    log 'Target packages installed. Database import and TLS remain separate stages.'
}

main "$@"
