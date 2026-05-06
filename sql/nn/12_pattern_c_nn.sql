-- 12_pattern_c_nn.sql
-- Pattern C for 1:N:N: Flat denormalized line-grain table
-- TWO guard flags — one per header grain above the line:
--   is_first_line_of_po    = 1 on first line of each PO    → guards po_total
--   is_first_line_of_order = 1 on first line of each order → guards order_total

USE bench;

DROP TABLE IF EXISTS po_flat_c_nn;

CREATE TABLE po_flat_c_nn
(
    -- Line-grain primary key
    po_id         UInt64,
    line_id       UInt32,

    -- Order-grain attributes (repeated 4×10=40 times per order)
    order_id      UInt64,
    customer_id   UInt32,
    order_date    Date,
    region        LowCardinality(String),
    order_status  LowCardinality(String),
    order_total   Decimal(18, 2),   -- ⚠ use sumIf(order_total, is_first_line_of_order=1)

    -- PO-grain attributes (repeated 10 times per PO)
    vendor_id     UInt32,
    po_date       Date,
    po_status     LowCardinality(String),
    po_total      Decimal(18, 2),   -- ⚠ use sumIf(po_total, is_first_line_of_po=1)

    -- Line-grain attributes (1 row each — always safe to SUM)
    product_id    UInt32,
    quantity      UInt32,
    unit_price    Decimal(18, 2),
    line_amount   Decimal(18, 2),   -- ✅ SUM directly

    -- Double-count guards — one per header grain
    is_first_line_of_po     UInt8,  -- 1 on the first line of each PO (10% of rows)
    is_first_line_of_order  UInt8   -- 1 on the first line of each order (2.5% of rows)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(po_date)
ORDER BY (po_date, vendor_id, order_id, po_id, line_id);
