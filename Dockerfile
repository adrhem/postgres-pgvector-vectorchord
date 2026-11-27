ARG VECTORCHORD_VERSION=1.5.0
ARG TARGETARCH

# VectorChord moved to pgsty/vchord; supervc-stack/VectorChord is no longer maintained.
# BuildKit verifies each download. Get new digests with:
# curl -fsSL https://api.github.com/repos/pgsty/vchord/releases/tags/VERSION | jq -r '.assets[] | "\(.name) \(.digest)"'
FROM scratch AS vectorchord-amd64
ARG VECTORCHORD_VERSION
ADD --checksum=sha256:ae2c40877942f4882c7ebb7ef02553e6f2c83d5800ae98bc8a9bdc92342edf9e \
    https://github.com/pgsty/vchord/releases/download/${VECTORCHORD_VERSION}/postgresql-19-vchord_${VECTORCHORD_VERSION}-1_amd64.deb /vectorchord.deb

FROM scratch AS vectorchord-arm64
ARG VECTORCHORD_VERSION
ADD --checksum=sha256:53d31a55d7591131772fd930507e2cd95c6041a352fd2e37846cf50c76740751 \
    https://github.com/pgsty/vchord/releases/download/${VECTORCHORD_VERSION}/postgresql-19-vchord_${VECTORCHORD_VERSION}-1_arm64.deb /vectorchord.deb

FROM vectorchord-${TARGETARCH} AS vectorchord

FROM postgres:19

# Signed PGDG package. Immich requires pgvector < 1.
ARG PGVECTOR_VERSION=0.8.7-2.pgdg13+1

LABEL org.opencontainers.image.title="PostgreSQL 19 + pgvector + VectorChord"
LABEL org.opencontainers.image.description="PostgreSQL 19 with pgvector and VectorChord for Immich and homelabs."
LABEL org.opencontainers.image.authors="Adrián HM <dev.foe555@slmail.me>"
LABEL org.opencontainers.image.source="https://github.com/adrhem/postgres-pgvector-vectorchord"
LABEL org.opencontainers.image.licenses="MIT"

# Install the extensions without keeping the downloaded package in a layer.
RUN --mount=from=vectorchord,source=/vectorchord.deb,target=/tmp/vectorchord.deb \
    apt-get update \
    && apt-get install -y --no-install-recommends "postgresql-${PG_MAJOR}-pgvector=${PGVECTOR_VERSION}" /tmp/vectorchord.deb \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 scripts/postgres-entrypoint.sh /usr/local/bin/postgres-entrypoint.sh

ENTRYPOINT ["postgres-entrypoint.sh"]
CMD ["postgres", "-c", "shared_preload_libraries=vchord"]
