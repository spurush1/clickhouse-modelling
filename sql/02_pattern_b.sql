-- 02_pattern_b.sql
-- Pattern B: Nested arrays — one row per PO, line items stored as parallel arrays
-- Header aggregations are naturally correct (no double-counting).
-- Line-level analysis requires ARRAY JOIN.

USE bench;

CREATE TABLE IF NOT EXISTS purchase_order_b
(
    po_id          UInt64,
    order_id       UInt64,
    vendor_id      UInt32,
    po_total       Decimal(18, 2),
    po_date        Date,
    po_status      LowCardinality(String),
    -- Parallel arrays: all must have the same length per row
    `lines.line_id`     Array(UInt32),
    `lines.product_id`  Array(UInt32),
    `lines.quantity`    Array(UInt32),
    `lines.unit_price`  Array(Decimal(18, 2)),
    `lines.line_amount` Array(Decimal(18, 2))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(po_date)
ORDER BY (order_id, po_id);

-- Separate order table for header lookups (needed for Q3/Q4 cross-grain)
CREATE TABLE IF NOT EXISTS order_b
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
