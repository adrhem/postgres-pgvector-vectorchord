\if :upgrade
ALTER EXTENSION vector UPDATE;
ALTER EXTENSION vchord UPDATE;
REINDEX INDEX smoke_vchord_idx;
SET enable_seqscan = off;
SELECT assert_vector_search('smoke_vchord_idx');

DROP INDEX smoke_vchord_idx;
CREATE INDEX smoke_hnsw_idx ON smoke_vectors USING hnsw (embedding vector_l2_ops);
SELECT assert_vector_search('smoke_hnsw_idx');
\else
CREATE EXTENSION vchord CASCADE;
CREATE EXTENSION earthdistance CASCADE;

CREATE TABLE smoke_vectors (id integer PRIMARY KEY, embedding vector(3));
INSERT INTO smoke_vectors
SELECT i, ARRAY[i::real, (i % 17)::real, (i % 31)::real]::vector
FROM generate_series(1, 1000) AS i;

CREATE FUNCTION assert_vector_search(expected_index text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    actual_id integer;
    query_plan json;
BEGIN
    SELECT id INTO actual_id FROM smoke_vectors
    ORDER BY embedding <-> '[42,8,11]'::vector LIMIT 1;
    IF actual_id IS DISTINCT FROM 42 THEN
        RAISE EXCEPTION 'Expected vector 42, got %', actual_id;
    END IF;

    EXECUTE $query$
        EXPLAIN (FORMAT JSON)
        SELECT id FROM smoke_vectors
        ORDER BY embedding <-> '[42,8,11]'::vector LIMIT 1
    $query$ INTO query_plan;
    IF query_plan::text NOT LIKE '%' || expected_index || '%' THEN
        RAISE EXCEPTION 'Expected index %, got plan %', expected_index, query_plan;
    END IF;
END;
$$;

CREATE INDEX smoke_vchord_idx ON smoke_vectors USING vchordrq (embedding vector_l2_ops);
ANALYZE smoke_vectors;
SET enable_seqscan = off;
SELECT assert_vector_search('smoke_vchord_idx');

DROP INDEX smoke_vchord_idx;
CREATE INDEX smoke_hnsw_idx ON smoke_vectors USING hnsw (embedding vector_l2_ops);
SELECT assert_vector_search('smoke_hnsw_idx');

-- Keep a VectorChord index on disk to exercise its upgrade, as used by Immich.
DROP INDEX smoke_hnsw_idx;
CREATE INDEX smoke_vchord_idx ON smoke_vectors USING vchordrq (embedding vector_l2_ops);
\endif

-- Immich requires pgvector < 0.9.
DO $$
BEGIN
    IF ((SELECT extversion FROM pg_extension WHERE extname = 'vector') ~ '^0\.8\.') IS NOT TRUE THEN
        RAISE EXCEPTION 'Immich requires pgvector 0.8.x';
    END IF;
END;
$$;

SELECT extname, extversion FROM pg_extension ORDER BY extname;
