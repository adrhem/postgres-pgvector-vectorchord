FROM postgres:18 AS builder

ENV PGVECTOR_VERSION="0.8.6"
ENV VECTORCHORD_VERSION="1.1.1"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    postgresql-server-dev-18 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/pgvector \
    && curl -fSL -o /tmp/pgvector.zip https://codeload.github.com/pgvector/pgvector/zip/refs/tags/v${PGVECTOR_VERSION} \
    && unzip /tmp/pgvector.zip -d /tmp/pgvector \
    && make -C /tmp/pgvector/pgvector-${PGVECTOR_VERSION} install \
    && rm -rf /tmp/pgvector*

RUN ARCH=$(dpkg --print-architecture) \
    && URL_VECTORCHORD="https://github.com/tensorchord/VectorChord/releases/download/${VECTORCHORD_VERSION}/postgresql-18-vchord_${VECTORCHORD_VERSION}-1_${ARCH}.deb" \
    && curl -fSL -o /tmp/vectorchord.deb "${URL_VECTORCHORD}" \
    && apt-get update && apt-get install -y /tmp/vectorchord.deb \
    && rm -rf /tmp/vectorchord.deb /var/lib/apt/lists/*


FROM postgres:18

ARG IMAGE_VERSION="1.0.1"

LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.title="PostgreSQL 18 + pgvector + VectorChord"
LABEL org.opencontainers.image.description="Personalized Docker image of PostgreSQL 18 (Latest) with pgvector and VectorChord extensions."
LABEL org.opencontainers.image.authors="Adrián HM <dev.foe555@slmail.me>"
LABEL org.opencontainers.image.source="https://github.com/adrhem/postgres-pgvector-vectorchord"
LABEL org.opencontainers.image.licenses="MIT"

COPY --from=builder /usr/lib/postgresql/18/lib/vector.so /usr/lib/postgresql/18/lib/
COPY --from=builder /usr/lib/postgresql/18/lib/vchord.so /usr/lib/postgresql/18/lib/
COPY --from=builder /usr/share/postgresql/18/extension/vector* /usr/share/postgresql/18/extension/
COPY --from=builder /usr/share/postgresql/18/extension/vchord* /usr/share/postgresql/18/extension/

CMD ["postgres", "-c", "shared_preload_libraries=vchord"]