# Zabbix Migration Toolkit

A staged migration toolkit for moving a Zabbix installation to a clean AlmaLinux 9 target while keeping database export, target preparation, import, TLS configuration, and validation as separate reviewable operations.

The repository is intentionally structured as a migration runbook rather than a single opaque auto-installer.

## Design goals

- preserve an auditable migration sequence;
- avoid database passwords in shell command-line arguments;
- create a checksummed migration artifact before cutover;
- refuse to import into a non-empty target database;
- keep TLS and firewall policy explicit;
- support Zabbix 7.0 LTS by default, with the branch configurable;
- retain the original repository history while replacing the unsafe legacy workflow.

## Workflow

```text
SOURCE                         TRANSFER                      TARGET

export-db.sh
    |
    +-- zabbix.sql.gz
    +-- SHA256SUMS
    +-- manifest.txt
             |
             +-------------------------> prepare-target.sh
                                         import-db.sh
                                         configure-tls.sh
                                         validate.sh
```

The toolkit does not perform source-to-target SSH or SCP by itself. Moving the migration artifact is an infrastructure/operator concern and can be done with SCP, rsync, Ansible, backup storage, or another controlled transfer mechanism.

## Repository structure

```text
.
├── README.md
├── config/
│   └── zabbix-migration.conf.example
├── lib/
│   └── common.sh
├── scripts/
│   ├── export-db.sh
│   ├── prepare-target.sh
│   ├── import-db.sh
│   ├── configure-tls.sh
│   └── validate.sh
└── .github/workflows/lint.yml
```

## Configuration

Install and edit the example configuration:

```bash
sudo install -d -m 0750 /etc/zabbix-migration
sudo install -m 0640 \
  config/zabbix-migration.conf.example \
  /etc/zabbix-migration.conf
```

Store the Zabbix database password separately:

```bash
sudo install -m 0600 /dev/null /etc/zabbix-migration/db-password
sudo editor /etc/zabbix-migration/db-password
```

MariaDB client credentials use root-only option files rather than `-pPASSWORD` command-line arguments.

Example source credentials file:

```ini
[client]
user=zabbix_backup
password=replace-me
host=127.0.0.1
```

Store it as `/root/.my-zabbix-source.cnf` with mode `0600`.

The target administrative client file follows the same model and defaults to `/root/.my.cnf`.

## 1. Source pre-cutover export

On the existing Zabbix server:

```bash
sudo ./scripts/export-db.sh /etc/zabbix-migration.conf
```

The result is a timestamped directory containing:

- compressed logical database dump;
- `SHA256SUMS`;
- a manifest containing timestamp, database name, source DB version, and intended Zabbix target branch.

The dump uses a single transaction for transactional tables and is tested with `gzip -t` before it is published as a migration artifact.

For a production cutover, quiesce configuration changes and data ingestion according to the selected migration/RPO plan before taking the final export.

## 2. Prepare the target

On a clean AlmaLinux 9 target:

```bash
sudo ./scripts/prepare-target.sh /etc/zabbix-migration.conf
```

This stage installs MariaDB, nginx, PHP/Zabbix frontend packages, Zabbix server and agent packages from the selected official Zabbix repository branch.

It does not run an interactive `mysql_secure_installation`, change firewalld policy, transfer databases, or generate credentials.

## 3. Transfer the artifact

Transfer the complete timestamped export directory using the site's approved method. Keep `zabbix.sql.gz`, `SHA256SUMS`, and `manifest.txt` together.

Example only:

```bash
rsync -a --progress \
  /var/backups/zabbix-migration/2026-09-15_10-00-00/ \
  target:/var/backups/zabbix-migration/2026-09-15_10-00-00/
```

## 4. Import the database

```bash
sudo ./scripts/import-db.sh \
  /etc/zabbix-migration.conf \
  /var/backups/zabbix-migration/2026-09-15_10-00-00
```

The importer:

- verifies the SHA-256 manifest;
- tests the gzip stream;
- refuses to continue when the target schema already contains tables;
- creates the database/user;
- imports the dump;
- checks that tables were created;
- writes the Zabbix DB settings to `zabbix_server.conf`.

## 5. Configure TLS

Two modes are supported.

### Existing certificate

Recommended for production:

```bash
TLS_MODE="existing"
TLS_CERT_FILE="/etc/pki/tls/certs/zabbix.crt"
TLS_KEY_FILE="/etc/pki/tls/private/zabbix.key"
```

The operator provisions the certificate and key using the site's PKI/ACME process.

### Self-signed certificate

Useful for a lab or initial internal validation:

```bash
TLS_MODE="self-signed"
```

Then run:

```bash
sudo ./scripts/configure-tls.sh /etc/zabbix-migration.conf
```

The generated private key is unencrypted so nginx can start unattended and is protected with filesystem permissions. This fixes the legacy design where an encrypted private key was generated without an unattended passphrase mechanism.

## 6. Validate

```bash
sudo ./scripts/validate.sh /etc/zabbix-migration.conf
```

The validation stage checks the core services and the local frontend endpoint. This is a technical smoke test; a production migration must additionally verify host availability, trigger processing, latest data, history/trends, media types, authentication, proxies, and representative dashboards.

## Security improvements over the legacy script

The original implementation was a useful automation experiment, but it combined too many privileged operations in one flow. The v2 branch removes or changes the following patterns:

- no hard-coded production IP addresses;
- no database passwords passed as `mysql -pPASSWORD` or `mysqldump -pPASSWORD`;
- no remote dump command embedding source credentials in SSH process arguments;
- no interactive `mysql_secure_installation` inside automation;
- no automatic firewall changes;
- no broad SELinux boolean changes without site review;
- no encrypted nginx key that requires an unavailable interactive passphrase at service start;
- no hand-built source-to-target migration that reports success without staged validation.

## Migration considerations

A database migration does not by itself guarantee a complete Zabbix service migration. Review separately:

- Zabbix server configuration outside DB settings;
- external scripts and alert scripts;
- custom modules and MIBs;
- TLS PSK/certificate material;
- SNMP traps;
- web server/frontend overrides;
- scripts used by media types;
- proxy compatibility and upgrade order;
- housekeeping and DB engine tuning;
- DNS/IP cutover;
- rollback criteria and rollback window.

For major Zabbix upgrades, test schema upgrade time on a copy of the production database before the maintenance window.

## CI

GitHub Actions runs Bash syntax checks and ShellCheck against the toolkit scripts.

CI is static validation only. Before production use, perform an end-to-end migration rehearsal using a disposable clone of the source database and target VM.

## Repository history

This repository consolidates the migration workflow and TLS handling that previously lived in separate experimental scripts. The historical `auto_cert_zabbix` repository has been retired after that consolidation.

## License

No license has been selected yet.
