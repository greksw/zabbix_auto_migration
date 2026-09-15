#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

CONFIG_FILE=${1:-/etc/zabbix-migration.conf}
ARTIFACT_DIR=${2:-}

main() {
    require_root
    load_config "${CONFIG_FILE}"
    [[ -n "${ARTIFACT_DIR}" ]] || fatal 'Usage: import-db.sh <config> <artifact-dir>'
    require_secret_file "${DB_ADMIN_CNF}"
    require_secret_file "${DB_PASSWORD_FILE}"
    require_command sha256sum
    require_command gzip

    local mysql_cmd dump_file db_password table_count
    mysql_cmd=$(mysql_client)
    dump_file="${ARTIFACT_DIR}/zabbix.sql.gz"
    [[ -f "${dump_file}" && -f "${ARTIFACT_DIR}/SHA256SUMS" ]] || fatal 'Migration artifact is incomplete.'

    (cd "${ARTIFACT_DIR}" && sha256sum -c SHA256SUMS)
    gzip -t "${dump_file}"
    db_password=$(read_secret "${DB_PASSWORD_FILE}")

    table_count=$("${mysql_cmd}" --defaults-extra-file="${DB_ADMIN_CNF}" --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")
    [[ ${table_count} == 0 ]] || fatal "Target database '${DB_NAME}' is not empty. Refusing import."

    log "Creating target database and user '${DB_USER}'."
    "${mysql_cmd}" --defaults-extra-file="${DB_ADMIN_CNF}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${db_password//\'/\'\'}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${db_password//\'/\'\'}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

    log 'Importing validated Zabbix database dump.'
    gzip -dc "${dump_file}" | "${mysql_cmd}" --defaults-extra-file="${DB_ADMIN_CNF}"

    table_count=$("${mysql_cmd}" --defaults-extra-file="${DB_ADMIN_CNF}" --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")
    (( table_count > 0 )) || fatal 'Import completed without creating tables.'

    install -d -m 0750 /etc/zabbix
    if grep -q '^DBName=' /etc/zabbix/zabbix_server.conf; then
        sed -i "s/^DBName=.*/DBName=${DB_NAME}/" /etc/zabbix/zabbix_server.conf
    else
        printf '\nDBName=%s\n' "${DB_NAME}" >> /etc/zabbix/zabbix_server.conf
    fi
    if grep -q '^DBUser=' /etc/zabbix/zabbix_server.conf; then
        sed -i "s/^DBUser=.*/DBUser=${DB_USER}/" /etc/zabbix/zabbix_server.conf
    else
        printf 'DBUser=%s\n' "${DB_USER}" >> /etc/zabbix/zabbix_server.conf
    fi
    if grep -q '^DBPassword=' /etc/zabbix/zabbix_server.conf; then
        sed -i "s/^DBPassword=.*/DBPassword=${db_password//&/\\&}/" /etc/zabbix/zabbix_server.conf
    else
        printf 'DBPassword=%s\n' "${db_password}" >> /etc/zabbix/zabbix_server.conf
    fi
    chmod 0640 /etc/zabbix/zabbix_server.conf

    log "Database import completed with ${table_count} tables."
}

main "$@"
