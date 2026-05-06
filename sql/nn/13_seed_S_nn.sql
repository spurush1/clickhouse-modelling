-- 13_seed_S_nn.sql
-- 1:N:N Tier S: 500 000 po_line rows
-- Cardinality: 12 500 orders × 4 POs × 10 lines = 500 000 lines
-- Each order has exactly 4 POs; each PO has exactly 10 lines

USE bench;

-- ── Pattern A ────────────────────────────────────────────────────────────────

INSERT INTO order_a_nn
SELECT
    number + 1                                        AS order_id,
    (rand() % 10000) + 1                              AS customer_id,
    toDate('2024-01-01') + (rand() % 365)             AS order_date,
    ['EMEA','APAC','AMER','LATAM'][rand() % 4 + 1]    AS region,
    ['OPEN','CLOSED','PENDING'][rand() % 3 + 1]       AS order_status,
    round(1000 + rand() % 49000, 2)                   AS order_total,
    1                                                 AS version
FROM numbers(12500);

INSERT INTO purchase_order_a_nn
SELECT
    number + 1                                                  AS po_id,
    intDiv(number, 4) + 1                                       AS order_id,   -- 4 POs per order
    (rand() % 500) + 1                                          AS vendor_id,
    round(100 + rand() % 9900, 2)                               AS po_total,
    toDate('2024-01-01') + (rand() % 365)                       AS po_date,
    ['ISSUED','RECEIVED','PARTIAL','CANCELLED'][rand() % 4 + 1] AS po_status,
    1                                                           AS version
FROM numbers(50000);

INSERT INTO po_line_a_nn
SELECT
    intDiv(number, 10) + 1                               AS po_id,       -- 10 lines per PO
    (number % 10) + 1                                    AS line_id,
    intDiv(intDiv(number, 10), 4) + 1                    AS order_id,    -- derived: po->order
    (rand() % 1000) + 1                                  AS product_id,
    (rand() % 100) + 1                                   AS quantity,
    round(1 + rand() % 999, 2)                           AS unit_price,
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2) AS line_amount,
    toDate('2024-01-01') + (rand() % 365)                AS line_date,
    1                                                    AS version
FROM numbers(500000);

-- ── Pattern B ────────────────────────────────────────────────────────────────

INSERT INTO order_b_nn
SELECT order_id, customer_id, order_date, region, order_status, order_total, version
FROM order_a_nn;

INSERT INTO purchase_order_b_nn
SELECT
    sub_po_id,
    any(sub_order_id),  any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date),   any(sub_po_status),
    groupArray(sub_line_id),    groupArray(sub_product_id),
    groupArray(sub_quantity),   groupArray(sub_unit_price),
    groupArray(sub_line_amount)
FROM (
    SELECT
        l.po_id        AS sub_po_id,
        p.order_id     AS sub_order_id,
        p.vendor_id    AS sub_vendor_id,
        p.po_total     AS sub_po_total,
        p.po_date      AS sub_po_date,
        p.po_status    AS sub_po_status,
        l.line_id      AS sub_line_id,
        l.product_id   AS sub_product_id,
        l.quantity     AS sub_quantity,
        l.unit_price   AS sub_unit_price,
        l.line_amount  AS sub_line_amount
    FROM po_line_a_nn AS l
    JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    ORDER BY l.po_id, l.line_id
)
GROUP BY sub_po_id;

-- ── Pattern C ────────────────────────────────────────────────────────────────

INSERT INTO po_flat_c_nn
SELECT
    l.po_id,
    l.line_id,
    o.order_id,
    o.customer_id,
    o.order_date,
    o.region,
    o.order_status,
    o.order_total,
    p.vendor_id,
    p.po_date,
    p.po_status,
    p.po_total,
    l.product_id,
    l.quantity,
    l.unit_price,
    l.line_amount,
    -- Guard 1: first line of each PO (1 of 10 rows per PO = 10% of rows)
    if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0)
        AS is_first_line_of_po,
    -- Guard 2: first line of the first PO of each order (1 of 40 rows per order = 2.5%)
    if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
       AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
        AS is_first_line_of_order
FROM po_line_a_nn AS l
JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn           AS o ON p.order_id = o.order_id;
