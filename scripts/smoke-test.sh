#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: bash scripts/smoke-test.sh IMAGE [docker run options]}
shift
container=
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
password=${SMOKE_POSTGRES_PASSWORD-test-only}
run_options=("$@")
volume=$(docker volume create)

cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$container" ]; then
    docker logs "$container" >&2 || true
  fi
  if [ -n "$container" ]; then
    docker rm --force "$container" >/dev/null 2>&1 || true
  fi
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_postgres() {
  for ((attempt = 0; attempt < 120; attempt++)); do
    # The initialization server only listens on a Unix socket. Checking TCP
    # avoids running tests before initdb and initialization scripts finish.
    if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres -d smoke >/dev/null 2>&1; then
      return 0
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' "$container")" != true ]; then
      break
    fi
    sleep 1
  done
  echo 'PostgreSQL did not become ready' >&2
  return 1
}

check_password() {
  docker exec --env SMOKE_PASSWORD="$password" "$container" sh -ec '
    if [ -n "$SMOKE_PASSWORD" ]; then
      test ! -e "${PGDATA}.password"
      PGPASSWORD=$SMOKE_PASSWORD
    else
      test "$(stat -c %a "${PGDATA}.password")" = 600
      PGPASSWORD=$(cat "${PGDATA}.password")
      test "${#PGPASSWORD}" = 64
    fi
    export PGPASSWORD
    psql -X -h 127.0.0.1 -U postgres -d smoke -v ON_ERROR_STOP=1 -c "SELECT 1" >/dev/null
  '
}

start_postgres() {
  container=$(docker run --detach --network none --shm-size 256m \
    --volume "$volume:/var/lib/postgresql" \
    --env POSTGRES_USER=postgres --env POSTGRES_DB=smoke \
    --env POSTGRES_PASSWORD="$password" \
    "${run_options[@]}" "$1")
  wait_for_postgres
  check_password
}

# PostgreSQL 18 upgrades only; use pg_upgrade or dump/restore for a new major.
start_postgres "${UPGRADE_FROM_IMAGE:-$image}"
docker exec -i "$container" psql -X -v ON_ERROR_STOP=1 -v upgrade=false -U postgres -d smoke < "$script_dir/smoke-test.sql"

docker stop --time 30 "$container" >/dev/null
docker rm "$container" >/dev/null
container=
start_postgres "$image"
count=$(docker exec "$container" psql -X -At -v ON_ERROR_STOP=1 -U postgres -d smoke \
  -c 'SELECT count(*) FROM smoke_vectors')
test "$count" = 1000
docker exec -i "$container" psql -X -v ON_ERROR_STOP=1 -v upgrade=true -U postgres -d smoke < "$script_dir/smoke-test.sql"
echo "Smoke tests passed: $image"
