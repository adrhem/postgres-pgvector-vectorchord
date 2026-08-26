FROM postgres:18

ARG IMAGE_VERSION="1.0.0"

LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.title="PostgreSQL 18 + pgvector + VectorChord"
LABEL org.opencontainers.image.description="Personalized Docker image of PostgreSQL 18 (Latest) with pgvector and VectorChord extensions."
LABEL org.opencontainers.image.authors="Adrián HM <dev.foe555@slmail.me>"
LABEL org.opencontainers.image.source="https://github.com/adrhem/postgres-pgvector-vectorchord"
LABEL org.opencontainers.image.licenses="MIT"

ENV POSTGRES_VERSION="18"
ENV PGVECTOR_VERSION="0.8.6"
ENV VECTORCHORD_VERSION="1.1.1"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    postgresql-server-dev-all \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# pgvector
RUN mkdir -p /tmp/pgvector \
    && cd /tmp/pgvector \
    && curl -o pgvector.zip https://codeload.github.com/pgvector/pgvector/zip/refs/tags/v${PGVECTOR_VERSION} \
    && unzip pgvector.zip \
    && cd pgvector-${PGVECTOR_VERSION} \
    && make \
    && make install \
    && rm -rf /tmp/pgvector

# VectorChord 
RUN mkdir -p /tmp/vectorchord \
    && cd /tmp/vectorchord \
    && ARCH=$(dpkg --print-architecture) \
    && URL_VECTORCHORD="https://github.com/tensorchord/VectorChord/releases/download/${VECTORCHORD_VERSION}/postgresql-${POSTGRES_VERSION}-vchord_${VECTORCHORD_VERSION}-1_${ARCH}.deb" \
    && curl -fSL -o vectorchord.deb "${URL_VECTORCHORD}" \
    && apt-get update && apt-get install -y ./vectorchord.deb \
    && cd / && rm -rf /tmp/vectorchord

# Cleanup
RUN apt-get purge -y --auto-remove build-essential curl unzip postgresql-server-dev-all

# Entry point
CMD ["postgres", "-c", "shared_preload_libraries=vchord"]