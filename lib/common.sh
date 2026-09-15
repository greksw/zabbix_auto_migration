#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fatal() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || fatal 'Run this command as root.'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

load_config() {
    local config_file=$1

    [[ -r "${config_file}" ]] || fatal "Configuration file is not readable: ${config_file}"

    # shellcheck disable=SC1090
    source "${config_file}"

    : "${ZABBIX_VERSION:=7.0}"
    : "${DB_NAME:=zabbix}"
    : "${DB_USER:=zabbix}"
    : "${DB_HOST:=localhost}"
    : "${DB_PASSWORD_FILE:=/etc/zabbix-migration/db-password}"
    : "${DB_ADMIN_CNF:=/root/.my.cnf}"
    : "${SOURCE_DB_CNF:=/root/.my-zabbix-source.cnf}"
    : "${BACKUP_DIR:=/var/backups/zabbix-migration}"
    : "${ZABBIX_SERVER_NAME:=zabbix.example.net}"
    : "${TLS_MODE:=existing}"
    : "${TLS_CERT_FILE:=/etc/pki/tls/certs/zabbix.crt}"
    : "${TLS_KEY_FILE:=/etc/pki/tls/private/zabbix.key}"
    : "${SELF_SIGNED_DAYS:=365}"

    [[ ${ZABBIX_VERSION} =~ ^[0-9]+\.[0-9]+$ ]] || fatal 'ZABBIX_VERSION must look like 7.0 or 7.4.'
    [[ ${DB_NAME} =~ ^[A-Za-z0-9_]+$ ]] || fatal 'DB_NAME contains unsupported characters.'
    [[ ${DB_USER} =~ ^[A-Za-z0-9_]+$ ]] || fatal 'DB_USER contains unsupported characters.'
    [[ ${TLS_MODE} == existing || ${TLS_MODE} == self-signed ]] \
        || fatal 'TLS_MODE must be existing or self-signed.'
    [[ ${SELF_SIGNED_DAYS} =~ ^[0-9]+$ ]] || fatal 'SELF_SIGNED_DAYS must be an integer.'
}

require_secret_file() {
    local path=$1
    local mode

    [[ -f "${path}" && -r "${path}" ]] || fatal "Secret file is not readable: ${path}"

    mode=$(stat -c '%a' "${path}")
    case "${mode}" in
        600|400) ;;
        *) fatal "Secret file ${path} must have mode 0600 or 0400 (current: ${mode})." ;;
    esac
}

read_secret() {
    local path=$1
    local value

    require_secret_file "${path}"
    IFS= read -r value < "${path}"
    [[ -n "${value}" ]] || fatal "Secret file is empty: ${path}"
    printf '%s' "${value}"
}

mysql_client() {
    if command -v mariadb >/dev/null 2>&1; then
        printf '%s\n' mariadb
    elif command -v mysql >/dev/null 2>&1; then
        printf '%s\n' mysql
    else
        fatal 'Neither mariadb nor mysql client is installed.'
    fi
}

mysqldump_client() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        printf '%s\n' mariadb-dump
    elif command -v mysqldump >/dev/null 2>&1; then
        printf '%s\n' mysqldump
    else
        fatal 'Neither mariadb-dump nor mysqldump is installed.'
    fi
}

require_almalinux_9() {
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ ${ID:-} == almalinux && ${VERSION_ID:-} == 9* ]] \
        || fatal 'Target preparation currently supports AlmaLinux 9 only.'
}
