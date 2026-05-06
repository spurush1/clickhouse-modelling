-- 03_pattern_c.sql
-- Pattern C: Flat denormalized table at line grain
-- All header fields repeated on every line row.
-- min_line_id carried per PO to enable double-count-safe header aggregations.

USE bench;

CREATE TABLE IF NOT EXISTS po_flat_c
(
    -- Line-grain key
    po_id           UInt64,
    line_id         UInt32,
    -- Denormalized PO header fields (repeated on every line row)
    order_id        UInt64,
    vendor_id       UInt32,
    po_total        Decimal(18, 2),   -- DO NOT sum directly — double-counting risk
    po_date         Date,
    po_status       LowCardinality(String),
    -- Denormalized order header fields
    customer_id     UInt32,
    order_date      Date,
    region          LowCardinality(String),
    -- Line-level fields (safe to sum directly)
    product_id      UInt32,
    quantity        UInt32,
    unit_price      Decimal(18, 2),
    line_amount     Decimal(18, 2),
    -- Marker for double-count-safe header aggregations:
    -- 1 on the first line per PO, 0 on all others
    is_first_line   UInt8
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(po_date)
ORDER BY (po_date, vendor_id, po_id, line_id);
