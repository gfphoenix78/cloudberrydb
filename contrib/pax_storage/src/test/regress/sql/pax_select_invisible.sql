--
-- Test gp_select_invisible for PAX tables
--
-- Verify that gp_select_invisible=true bypasses the PAX visibility bitmap so
-- that deleted tuples are exposed via both sequential scan and index scan.
-- Also verify that VACUUM (which uses SNAPSHOT_ANY internally) can scan a PAX
-- index without crashing.
--

-- Sequential scan: deleted rows should be visible when gp_select_invisible=true

CREATE TABLE pax_seqscan_invisible (id int, val text)
    USING pax DISTRIBUTED BY (id);

INSERT INTO pax_seqscan_invisible
    SELECT i, 'row ' || i FROM generate_series(1, 5) i;

-- Baseline: normal scan returns all 5 rows
SELECT * FROM pax_seqscan_invisible ORDER BY id;

-- Delete rows with even id (id=2 and id=4)
DELETE FROM pax_seqscan_invisible WHERE id % 2 = 0;

-- Normal scan now returns only 3 rows (deleted rows hidden by visimap)
SELECT * FROM pax_seqscan_invisible ORDER BY id;

-- With gp_select_invisible=true, sequential scan bypasses the visimap and
-- returns all 5 physical rows (including deleted ones)
SET gp_select_invisible = true;
SET enable_seqscan = on;
SET enable_indexscan = off;
SET enable_bitmapscan = off;

SELECT count(*) FROM pax_seqscan_invisible;

RESET gp_select_invisible;
RESET enable_seqscan;
RESET enable_indexscan;
RESET enable_bitmapscan;

DROP TABLE pax_seqscan_invisible;

-- Index scan: deleted rows should be visible when gp_select_invisible=true
-- The btree index retains entries for deleted tuples until VACUUM.
-- FetchTuple must also bypass the visimap check when gp_select_invisible=true.

CREATE TABLE pax_idxscan_invisible (id int, val text)
    USING pax DISTRIBUTED BY (id);

INSERT INTO pax_idxscan_invisible
    SELECT i, 'row ' || i FROM generate_series(1, 5) i;

-- Create a btree index used by the index-scan path
CREATE INDEX pax_idxscan_invisible_id_idx ON pax_idxscan_invisible (id);

-- Delete rows with even id (id=2 and id=4)
DELETE FROM pax_idxscan_invisible WHERE id % 2 = 0;

-- Normal index scan returns only 3 rows
SET enable_seqscan = off;
SET enable_indexscan = on;
SET enable_bitmapscan = off;

SELECT count(*) FROM pax_idxscan_invisible WHERE id > 0;

-- With gp_select_invisible=true, index scan follows all index entries and
-- bypasses the visimap check in FetchTuple, exposing all 5 physical rows
SET gp_select_invisible = true;

SELECT count(*) FROM pax_idxscan_invisible WHERE id > 0;

RESET gp_select_invisible;
RESET enable_seqscan;
RESET enable_indexscan;
RESET enable_bitmapscan;

-- VACUUM uses SNAPSHOT_ANY when scanning indexes.  Previously, PAX was passing
-- SNAPSHOT_ANY to catalog lookups, which could cause incorrect behavior.
-- After the fix, catalog lookups use GetCatalogSnapshot instead.
-- Verify VACUUM completes without error on a PAX table with an index.
VACUUM pax_idxscan_invisible;

DROP TABLE pax_idxscan_invisible;
