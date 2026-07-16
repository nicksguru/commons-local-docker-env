#!/bin/bash
#
# This script is executed by parent container only once.
#
set -e

if [ -n "$POSTGRES_REPLICATE_FROM_HOST" ]; then
  echo "This is a secondary node - not creating any databases or tables explicitly"
  exit
fi

# Create more databases and grant $POSTGRES_USER (which is the root DB user, by design) access to them.
# No password is requires because Postgres trusts the Unix socket.
for db in $SQL_MORE_DATABASES; do
    echo "Creating database: $db"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOF
        CREATE DATABASE $db;
        GRANT ALL PRIVILEGES ON DATABASE $db TO $POSTGRES_USER;
EOF
done

# Vault PostgreSQL plugin doesn't auto-create the tables (unlike its MySQL plugin)
echo "Creating table: $SQL_VAULT_DATABASE.$SQL_VAULT_TABLE"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$SQL_VAULT_DATABASE" <<-EOF
    CREATE TABLE $SQL_VAULT_TABLE (
        parent_path TEXT COLLATE "C" NOT NULL,
        path        TEXT COLLATE "C",
        key         TEXT COLLATE "C",
        value       BYTEA,
        CONSTRAINT pkey PRIMARY KEY (path, key)
    );

    CREATE INDEX parent_path_idx ON $SQL_VAULT_TABLE (parent_path);

    CREATE TABLE vault_ha_locks (
        ha_key                                      TEXT COLLATE "C" NOT NULL,
        ha_identity                                 TEXT COLLATE "C" NOT NULL,
        ha_value                                    TEXT COLLATE "C",
        valid_until                                 TIMESTAMP WITH TIME ZONE NOT NULL,
        CONSTRAINT ha_key PRIMARY KEY (ha_key)
    );
EOF
