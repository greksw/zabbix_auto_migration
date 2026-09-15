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
    require_command python3

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
    DB_PASSWORD="${db_password}" "${mysql_cmd}" --defaults-extra-file="${DB_ADMIN_CNF}" <<SQL
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

    DB_NAME_VALUE="${DB_NAME}" DB_USER_VALUE="${DB_USER}" DB_PASSWORD_VALUE="${db_password}" python3 - <<'PY'
from pathlib import Path
import os

path = Path('/etc/zabbix/zabbix_server.conf')
text = path.read_text(encoding='utf-8') if path.exists() else ''
values = {
    'DBName': os.environ['DB_NAME_VALUE'],
    'DBUser': os.environ['DB_USER_VALUE'],
    'DBPassword': os.environ['DB_PASSWORD_VALUE'],
}
lines = text.splitlines()
for key, value in values.items():
    prefix = key + '='
    replaced = False
    for idx, line in enumerate(lines):
        if line.startswith(prefix):
            lines[idx] = prefix + value
            replaced = True
            break
    if not replaced:
        lines.append(prefix + value)
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
    chmod 0640 /etc/zabbix/zabbix_server.conf

    log "Database import completed with ${table_count} tables."
}

main "$@"
