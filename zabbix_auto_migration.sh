#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
    cat <<'EOF'
Usage:
  zabbix_auto_migration.sh export   [config]
  zabbix_auto_migration.sh prepare  [config]
  zabbix_auto_migration.sh import   [config] <artifact-dir>
  zabbix_auto_migration.sh tls      [config]
  zabbix_auto_migration.sh validate [config]

Default config: /etc/zabbix-migration.conf
EOF
}

stage=${1:-}
config=${2:-/etc/zabbix-migration.conf}

case "${stage}" in
    export)
        exec "${SCRIPT_DIR}/scripts/export-db.sh" "${config}"
        ;;
    prepare)
        exec "${SCRIPT_DIR}/scripts/prepare-target.sh" "${config}"
        ;;
    import)
        artifact=${3:-}
        [[ -n "${artifact}" ]] || { usage >&2; exit 2; }
        exec "${SCRIPT_DIR}/scripts/import-db.sh" "${config}" "${artifact}"
        ;;
    tls)
        exec "${SCRIPT_DIR}/scripts/configure-tls.sh" "${config}"
        ;;
    validate)
        exec "${SCRIPT_DIR}/scripts/validate.sh" "${config}"
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
