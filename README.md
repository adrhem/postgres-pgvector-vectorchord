# PostgreSQL + pgvector + VectorChord

PostgreSQL 19 with [pgvector 0.8.7](https://github.com/pgvector/pgvector) and
[VectorChord 1.5.0](https://github.com/pgsty/vchord), for Immich and homelabs.
AMD64 and ARM64. Coming from PostgreSQL 18? See
[Upgrade from PostgreSQL 18](#upgrade-from-postgresql-18).

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

| Tag                  | Use                                                                 |
| -------------------- | ------------------------------------------------------------------- |
| `19`                 | Recommended. Latest release for PostgreSQL 19.                      |
| `19-1.2.3`, `19-1.2` | Pin a release.                                                      |
| `18`                 | Final PostgreSQL 18 release (`18-3.0.0`). No further updates.       |
| `latest`             | Avoid. It moves to each new PostgreSQL major, which won't start on old data. |

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
as `external: true` in its Compose file) and connect to `db:5432`. Immich requires
pgvector below 1 and VectorChord below 2; see Immich's
[standalone PostgreSQL guide](https://docs.immich.app/administration/postgres-standalone/).

Immich v3.4.2 runs on PostgreSQL 19, but its built-in database backups and restores
do not: it only bundles `pg_dump` for PostgreSQL 14 to 18. Back up with the
`pg_dump` command in [Backups and updates](#backups-and-updates), or stay on `18`
until Immich supports 19.

## Backups and updates

```sh
mkdir -p backups && umask 077
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -Fc immich' > backups/immich.dump
docker compose pull && docker compose up -d --wait
```

Keep a copy off the server, test restoring it, and back up Immich's photos
separately. `docker compose down -v` deletes the databases.

A new major image version (for example `19-3.x` to `19-4.0.0`) updates pgvector or
VectorChord. The `19` tag gets these too, so check the release notes before pulling.
Stop Immich first: it does not start until the extensions are updated. After
pulling, run this in every database that uses the extensions, then start Immich:

```sh
docker compose exec db sh -c 'exec psql -X -U "$POSTGRES_USER" -d immich -c "ALTER EXTENSION vector UPDATE" -c "ALTER EXTENSION vchord UPDATE"'
```

Reindex vector indexes if the release notes say so. A new PostgreSQL major version
needs a dump and restore, as below.

## Upgrade from PostgreSQL 18

The `19` image refuses to start while PostgreSQL 18 data is in the volume. Dump
everything, move the old data aside in the same volume, and restore. You need free
space for the dump and a second copy of the data.

1. Stop every app that uses the database, such as Immich.
2. Dump all databases and roles:

   ```sh
   mkdir -p backups && umask 077
   docker compose exec -T db sh -c 'exec pg_dumpall -U "$POSTGRES_USER"' > backups/all-18.sql
   ```

3. Set the image to `:19` in `compose.yml` (or pull this repository), then move the
   18 data aside. The second line keeps a generated password.

   ```sh
   docker compose down && docker compose pull
   docker compose run --rm --no-deps --entrypoint sh db -ec 'cd /var/lib/postgresql && mv 18/docker 18/docker-old
     if [ -s 18/docker.password ]; then install -d -o postgres -g postgres 19 && cp -p 18/docker.password 19/; fi'
   docker compose up -d --wait
   ```

4. Restore. The `sed` keeps Immich's `earthdistance` functions working, as in
   Immich's own restore guide:

   ```sh
   sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" backups/all-18.sql \
     | docker compose exec -T db sh -c 'exec psql -X -U "$POSTGRES_USER" -d postgres'
   ```

   The only expected error is `role "<POSTGRES_USER>" already exists`. Roles,
   passwords and databases come back as they were, and VectorChord indexes are
   rebuilt during the restore.

5. Start the apps and check them. Once you are happy, delete the old data:
   `docker compose exec db rm -rf /var/lib/postgresql/18`.

To go back before that, run `docker compose down`, set the image to `:18`, and run
`docker compose run --rm --no-deps --entrypoint mv db /var/lib/postgresql/18/docker-old /var/lib/postgresql/18/docker`.

## Development

```sh
docker build -t postgres-test:local .
bash scripts/smoke-test.sh postgres-test:local
SMOKE_POSTGRES_PASSWORD='' bash scripts/smoke-test.sh postgres-test:local   # generated password
UPGRADE_FROM_IMAGE=ghcr.io/adrhem/postgres-pgvector-vectorchord:OLD_TAG \
  bash scripts/smoke-test.sh postgres-test:local                            # upgrade from an older 19 image
```

The tests use a throwaway container and volume. They check VectorChord and HNSW
search, password authentication, and a container replacement with extension updates.

To release, push a tag `v<PostgreSQL major>-<version>`, for example `v19-1.2.3`. CI
tests both architectures, then publishes `19-1.2.3`, `19-1.2`, `19` and `latest`.
It rejects any other tag format. Pull requests are tested without publishing.
Bump the major image version whenever pgvector or VectorChord changes.
