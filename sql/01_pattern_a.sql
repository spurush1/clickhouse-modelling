-- 01_pattern_a.sql
-- Pattern A: Two co-sorted ReplacingMergeTree tables + HASHED dictionary
-- Enables full_sorting_merge joins (sort phase skipped when ORDER BY matches join key)

USE bench;

-- Top-level order table
CREATE TABLE IF NOT EXISTS order_a
(
    order_id       UInt64,
    customer_id    UInt32,
    order_date     Date,
    region         LowCardinality(String),
    order_status   LowCardinality(String),
    version        UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(order_date)
ORDER BY order_id;

-- Purchase order table — co-sorted with order_a on leading order_id column
CREATE TABLE IF NOT EXISTS purchase_order_a
(
    po_id          UInt64,
    order_id       UInt64,
    vendor_id      UInt32,
    po_total       Decimal(18, 2),
    po_date        Date,
    po_status      LowCardinality(String),
    version        UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(po_date)
ORDER BY (order_id, po_id);

-- PO line table — co-sorted with purchase_order_a on leading po_id column
-- order_id denormalized here to enable skipping the middle table when PO attributes not needed
CREATE TABLE IF NOT EXISTS po_line_a
(
    po_id          UInt64,
    line_id        UInt32,
    order_id       UInt64,    -- denormalized from purchase_order at insert time
    product_id     UInt32,
    quantity       UInt32,
    unit_price     Decimal(18, 2),
    line_amount    Decimal(18, 2),
    line_date      Date,
    version        UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(line_date)
ORDER BY (po_id, line_id);

-- Dictionary backed by order_a for fast dictGet lookups (avoids join to top-level table)
CREATE DICTIONARY IF NOT EXISTS order_dict
(
    order_id     UInt64,
    customer_id  UInt32,
    order_date   Date,
    region       String,
    order_status String
)
PRIMARY KEY order_id
SOURCE(CLICKHOUSE(TABLE 'order_a' DB 'bench'))
LAYOUT(HASHED())
LIFETIME(MIN 300 MAX 600);
