# PostgreSQL + pgvector + VectorChord

PostgreSQL 18 with [pgvector 0.8.7](https://github.com/pgvector/pgvector) and
[VectorChord 1.1.1](https://github.com/supervc-stack/VectorChord), for Immich and
homelabs. AMD64 and ARM64.

## Start

```sh
cp .env.example .env   # set user, password and initial database
docker compose up -d --wait
```

PostgreSQL listens on `127.0.0.1:5432`. To accept other machines, set
`POSTGRES_BIND_IP=0.0.0.0` in `.env`. Docker bypasses host firewalls such as `ufw`,
so only do this on a trusted network.

With an empty `POSTGRES_PASSWORD`, a password is generated on first start:

```sh
docker compose exec db sh -c 'cat "${PGDATA}.password"'
```

Editing `.env` later does not change an existing database's password.
For a local build: `docker compose -f compose.dev.yml up -d --build --wait`.

## Tags

| Tag                  | Use                                                            |
| -------------------- | -------------------------------------------------------------- |
| `18`                 | Recommended. Latest release for PostgreSQL 18.                 |
| `18-1.2.3`, `18-1.2` | Pin a release.                                                 |
| `latest`             | Avoid. It will move to PostgreSQL 19, which won't start on 18 data. |

## Immich

Open a `psql` session and create the database:

```sh
docker compose exec db sh -c 'exec psql -X -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

```sql
CREATE ROLE immich LOGIN;
\password immich
CREATE DATABASE immich OWNER immich;
\connect immich
CREATE EXTENSION vchord CASCADE;
CREATE EXTENSION earthdistance CASCADE;
```

Attach Immich to the Docker network `postgres-pgvector-vectorchord_default` (declared
as `external: true` in its Compose file) and connect to `db:5432`. pgvector stays on
0.8.x while Immich requires a version below 0.9; see Immich's
[standalone PostgreSQL guide](https://docs.immich.app/administration/postgres-standalone/).

## Backups and updates

```sh
mkdir -p backups && umask 077
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -Fc immich' > backups/immich.dump
docker compose pull && docker compose up -d --wait
```

Keep a copy off the server, test restoring it, and back up Immich's photos
separately. `docker compose down -v` deletes the databases.

New extension versions may need `ALTER EXTENSION vector UPDATE`,
`ALTER EXTENSION vchord UPDATE` and a reindex; follow their release notes.
A new PostgreSQL major version needs `pg_upgrade` or dump/restore.

## Development

```sh
docker build -t postgres-test:local .
bash scripts/smoke-test.sh postgres-test:local
SMOKE_POSTGRES_PASSWORD='' bash scripts/smoke-test.sh postgres-test:local   # generated password
UPGRADE_FROM_IMAGE=ghcr.io/adrhem/postgres-pgvector-vectorchord:OLD_TAG \
  bash scripts/smoke-test.sh postgres-test:local                            # upgrade from an 18 image
```

The tests use a throwaway container and volume. They check VectorChord and HNSW
search, password authentication, and a container replacement with extension updates.

To release, push a tag `v<PostgreSQL major>-<version>`, for example `v18-1.2.3`. CI
tests both architectures, then publishes `18-1.2.3`, `18-1.2`, `18` and `latest`.
It rejects any other tag format. Pull requests are tested without publishing.
