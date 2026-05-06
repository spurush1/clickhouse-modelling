-- 10_pattern_a_nn.sql
-- Pattern A for 1:N:N: order -> purchase_order -> po_line
-- Three co-sorted ReplacingMergeTree tables + HASHED dictionary on order
-- order now has its own order_total field (separate from po_total)

USE bench;

DROP TABLE IF EXISTS order_a_nn;
DROP TABLE IF EXISTS purchase_order_a_nn;
DROP TABLE IF EXISTS po_line_a_nn;
DROP DICTIONARY IF EXISTS order_dict_nn;

CREATE TABLE order_a_nn
(
    order_id      UInt64,
    customer_id   UInt32,
    order_date    Date,
    region        LowCardinality(String),
    order_status  LowCardinality(String),
    order_total   Decimal(18, 2),   -- header-grain metric at order level
    version       UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(order_date)
ORDER BY order_id;

CREATE TABLE purchase_order_a_nn
(
    po_id       UInt64,
    order_id    UInt64,
    vendor_id   UInt32,
    po_total    Decimal(18, 2),   -- header-grain metric at PO level
    po_date     Date,
    po_status   LowCardinality(String),
    version     UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(po_date)
ORDER BY (order_id, po_id);      -- co-sorted with order_a_nn on order_id

CREATE TABLE po_line_a_nn
(
    po_id       UInt64,
    line_id     UInt32,
    order_id    UInt64,           -- denormalized FK
    product_id  UInt32,
    quantity    UInt32,
    unit_price  Decimal(18, 2),
    line_amount Decimal(18, 2),
    line_date   Date,
    version     UInt64
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(line_date)
ORDER BY (po_id, line_id);       -- co-sorted with purchase_order_a_nn on po_id

CREATE DICTIONARY order_dict_nn
(
    order_id     UInt64,
    customer_id  UInt32,
    order_date   Date,
    region       String,
    order_status String,
    order_total  Decimal(18, 2)
)
PRIMARY KEY order_id
SOURCE(CLICKHOUSE(TABLE 'order_a_nn' DB 'bench'))
LAYOUT(HASHED())
LIFETIME(MIN 300 MAX 600);
