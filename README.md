## PostgreSQL for Immich and homelabs

PostgreSQL 18 with [pgvector 0.8.7](https://github.com/pgvector/pgvector) and
[VectorChord 1.1.1](https://github.com/supervc-stack/VectorChord), published for
AMD64 and ARM64. Build tools stay out of the final image, and pgvector is compiled
for portability between CPUs. The Dockerfile contains the dependency versions.

### Start

```sh
cp .env.example .env
# Set your user, a strong password and the initial database in .env.
docker compose up -d --wait
```

`compose.yml` uses the published `latest` image. PostgreSQL is available at
`YOUR_SERVER_IP:5432`. The three `.env` values are the only usual configuration.
For a local build, use `docker compose -f compose.dev.yml up -d --build --wait`.

The image also runs without a supplied password: the entrypoint generates one for
a new database and saves it alongside `PGDATA` inside the persistent volume. Read
it with `docker compose exec db sh -c 'cat "${PGDATA}.password"'`. Explicit passwords
and `POSTGRES_PASSWORD_FILE` take precedence. Existing databases keep their
credentials; editing `.env` does not change an existing database's password.

The named volume `postgres_data` is mounted at `/var/lib/postgresql`, preserving
the original project name and volume. Both Compose files use `shm_size: 256mb`
(the shared-memory limit, not reserved RAM) and allow one minute for shutdown.

### Immich and other applications

Use a separate database and login for each app. Open an administrator session:

```sh
docker compose exec db sh -c 'exec psql -X -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

For a new Immich database, run:

```sql
CREATE ROLE immich LOGIN;
\password immich
CREATE DATABASE immich OWNER immich;
\connect immich
CREATE EXTENSION vchord CASCADE;
CREATE EXTENSION earthdistance CASCADE;
```

Configure Immich with that database's credentials. Check its
[standalone PostgreSQL guide](https://docs.immich.app/administration/postgres-standalone/)
for compatibility with the Immich version you run.

Apps can connect through port `5432`, or join Docker network
`postgres-pgvector-vectorchord_default` and use `db:5432`. In another Compose
project, declare that network as `external: true` and attach the app to it.
The port is published on the server's interfaces; keep access within your trusted
homelab network.

### Updates and backups

Before updating, back up each application database. For example, for Immich:

```sh
mkdir -p backups
umask 077
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -Fc immich' > backups/immich.dump
```

Keep a copy off the server and test restoring it. Back up application files such
as Immich's photos separately. To update the container:

```sh
docker compose pull
docker compose up -d --wait
```

Recreating the container reuses the volume. Avoid `docker compose down -v` unless
you intend to delete the databases. To choose a specific release, edit `image:`
in `compose.yml` instead of using `latest`.

For PostgreSQL 18 updates, the data directory stays in place. New extension
versions may need `ALTER EXTENSION vector UPDATE`, `ALTER EXTENSION vchord UPDATE`
and reindexing in each affected database; follow their release instructions.
Changing PostgreSQL's major version requires `pg_upgrade` or dump/restore.

### Tests and publishing

Build and test without touching your databases:

```sh
docker build -t postgres-test:local .
bash scripts/smoke-test.sh postgres-test:local
# Also check automatic password generation:
SMOKE_POSTGRES_PASSWORD='' bash scripts/smoke-test.sh postgres-test:local
```

The SQL creates sample vectors and indexes, checks nearest-neighbor results, and
reuses a temporary volume in a replacement container. It then updates extensions,
reindexes the existing VectorChord index and checks both VectorChord and HNSW.
The script checks password authentication before and after replacement and cleans
up its own container and volume.

To test an upgrade from an older PostgreSQL 18 image, supply its tag or digest:

```sh
UPGRADE_FROM_IMAGE=ghcr.io/adrhem/postgres-pgvector-vectorchord:OLD_TAG \
  bash scripts/smoke-test.sh postgres-test:local
```

GitHub Actions runs these checks for AMD64 and ARM64 before publishing. A stable
tag such as `v1.2.3` publishes `1.2.3`, `1.2` and `latest`; manual builds publish a
commit tag. Image version labels come from GitHub, without `IMAGE_VERSION` in the
Dockerfile. Pull requests run the checks without publishing.
