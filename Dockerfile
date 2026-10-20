FROM postgres:18 AS builder

ARG PGVECTOR_VERSION=0.8.7
ARG VECTORCHORD_VERSION=1.1.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    postgresql-server-dev-18 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/pgvector \
    && curl -fSL --retry 3 -o /tmp/pgvector.zip "https://codeload.github.com/pgvector/pgvector/zip/refs/tags/v${PGVECTOR_VERSION}" \
    && unzip /tmp/pgvector.zip -d /tmp/pgvector \
    && make -C "/tmp/pgvector/pgvector-${PGVECTOR_VERSION}" -j"$(nproc)" OPTFLAGS="" install \
    && rm -rf /tmp/pgvector*

RUN ARCH=$(dpkg --print-architecture) \
    && URL_VECTORCHORD="https://github.com/supervc-stack/VectorChord/releases/download/${VECTORCHORD_VERSION}/postgresql-18-vchord_${VECTORCHORD_VERSION}-1_${ARCH}.deb" \
    && curl -fSL --retry 3 -o /tmp/vectorchord.deb "${URL_VECTORCHORD}"

FROM postgres:18

LABEL org.opencontainers.image.title="PostgreSQL 18 + pgvector + VectorChord"
LABEL org.opencontainers.image.description="PostgreSQL 18 with pgvector and VectorChord for Immich and homelabs."
LABEL org.opencontainers.image.authors="Adrián HM <dev.foe555@slmail.me>"
LABEL org.opencontainers.image.source="https://github.com/adrhem/postgres-pgvector-vectorchord"
LABEL org.opencontainers.image.licenses="MIT"

COPY --from=builder /usr/lib/postgresql/18/lib/vector.so /usr/lib/postgresql/18/lib/
COPY --from=builder /usr/share/postgresql/18/extension/vector* /usr/share/postgresql/18/extension/

# Install runtime dependencies without keeping the downloaded package in a layer.
RUN --mount=from=builder,source=/tmp/vectorchord.deb,target=/tmp/vectorchord.deb \
    apt-get update \
    && apt-get install -y --no-install-recommends /tmp/vectorchord.deb \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 scripts/postgres-entrypoint.sh /usr/local/bin/postgres-entrypoint.sh

ENTRYPOINT ["postgres-entrypoint.sh"]
CMD ["postgres", "-c", "shared_preload_libraries=vchord"]
