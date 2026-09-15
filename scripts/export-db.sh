#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

CONFIG_FILE="${1:-/etc/zabbix-migration.conf}"

main() {
    load_config "${CONFIG_FILE}"
    require_command sha256sum
    require_secret_file "${SOURCE_DB_CNF}"

    local dump_cmd mysql_cmd timestamp out_dir dump_file manifest_file
    dump_cmd=$(mysqldump_client)
    mysql_cmd=$(mysql_client)
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    out_dir="${BACKUP_DIR}/${timestamp}"
    dump_file="${out_dir}/zabbix.sql.gz"
    manifest_file="${out_dir}/manifest.txt"

    install -d -m 0750 "${out_dir}"

    log "Checking source database '${DB_NAME}'."
    "${mysql_cmd}" --defaults-extra-file="${SOURCE_DB_CNF}" \
        --batch --skip-column-names \
        -e "SELECT COUNT(*) FROM ${DB_NAME}.users;" >/dev/null

    log 'Creating consistent logical dump.'
    "${dump_cmd}" \
        --defaults-extra-file="${SOURCE_DB_CNF}" \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --databases "${DB_NAME}" \
        | gzip -9 > "${dump_file}.tmp"

    gzip -t "${dump_file}.tmp"
    mv -- "${dump_file}.tmp" "${dump_file}"
    chmod 0640 "${dump_file}"

    (
        cd "${out_dir}"
        sha256sum "$(basename "${dump_file}")" > SHA256SUMS
        chmod 0640 SHA256SUMS
    )

    {
        printf 'created_at=%s\n' "$(date --iso-8601=seconds)"
        printf 'database=%s\n' "${DB_NAME}"
        printf 'zabbix_target_branch=%s\n' "${ZABBIX_VERSION}"
        printf 'source_db_version=%s\n' "$("${mysql_cmd}" --defaults-extra-file="${SOURCE_DB_CNF}" --batch --skip-column-names -e 'SELECT VERSION();')"
        printf 'dump_file=%s\n' "$(basename "${dump_file}")"
    } > "${manifest_file}"
    chmod 0640 "${manifest_file}"

    log "Export completed: ${out_dir}"
    printf '%s\n' "${out_dir}"
}

main "$@"
