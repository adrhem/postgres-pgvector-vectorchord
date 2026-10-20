#!/usr/bin/env bash
set -Eeuo pipefail

if [ "${1:-}" = postgres ] || [[ "${1:-}" = -* ]]; then
  for argument in "$@"; do
    case "$argument" in
      '-?'|--help|--describe-config|-V|--version)
        exec /usr/local/bin/docker-entrypoint.sh "$@"
        ;;
    esac
  done

  # Existing clusters keep their credentials. For a new cluster, explicit
  # passwords, password files and an explicit trust setting take precedence.
  if [ ! -s "${PGDATA}/PG_VERSION" ] \
    && [ -z "${POSTGRES_PASSWORD:-}" ] \
    && [ -z "${POSTGRES_PASSWORD_FILE:-}" ] \
    && [ "${POSTGRES_HOST_AUTH_METHOD:-}" != trust ]; then
    password_file="${PGDATA}.password"
    mkdir -p -- "$(dirname -- "$password_file")"
    if [ ! -s "$password_file" ]; then
      (
        umask 077
        od -An -N32 -tx1 -v /dev/urandom | tr -d ' \n' > "$password_file"
      )
    fi
    export POSTGRES_PASSWORD_FILE="$password_file"
  fi
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
