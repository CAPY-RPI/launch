#!/bin/bash
set -e

# This script initializes the PostgreSQL databases for multiple services
# using environment variables provisioned by Terraform.

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
	-- 1. Create the Authentik User and Database
	CREATE USER authentik_user WITH PASSWORD '$AUTHENTIK_POSTGRES_PASSWORD';
	CREATE DATABASE authentik_db OWNER authentik_user;
	GRANT ALL PRIVILEGES ON DATABASE authentik_db TO authentik_user;

	-- 2. Create the Capy User and Database
	CREATE USER capy_user WITH PASSWORD '$CAPY_POSTGRES_PASSWORD';
	CREATE DATABASE capy_db OWNER capy_user;
	GRANT ALL PRIVILEGES ON DATABASE capy_db TO capy_user;

	-- Finalize permissions for PostgreSQL 15+
	\c authentik_db
	GRANT ALL ON SCHEMA public TO authentik_user;

	\c capy_db
	GRANT ALL ON SCHEMA public TO capy_user;
EOSQL
