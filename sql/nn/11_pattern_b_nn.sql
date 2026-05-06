-- 11_pattern_b_nn.sql
-- Pattern B for 1:N:N: Nested arrays, one row per PO
-- order_b_nn holds order-level data; purchase_order_b_nn holds PO + lines arrays

USE bench;

DROP TABLE IF EXISTS purchase_order_b_nn;
DROP TABLE IF EXISTS order_b_nn;

CREATE TABLE order_b_nn
(
    order_id      UInt64,
    customer_id   UInt32,
    order_date    Date,
    region        LowCardinality(String),
    order_status  LowCardinality(String),
    order_total   Decimal(18, 2),
    version       UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(order_date)
ORDER BY order_id;

CREATE TABLE purchase_order_b_nn
(
    po_id     UInt64,
    order_id  UInt64,
    vendor_id UInt32,
    po_total  Decimal(18, 2),
    po_date   Date,
    po_status LowCardinality(String),
    -- Parallel arrays for line items
    `lines.line_id`     Array(UInt32),
    `lines.product_id`  Array(UInt32),
    `lines.quantity`    Array(UInt32),
    `lines.unit_price`  Array(Decimal(18, 2)),
    `lines.line_amount` Array(Decimal(18, 2))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(po_date)
ORDER BY (order_id, po_id);
