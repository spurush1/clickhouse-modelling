-- 04_seed_S.sql
-- Seed tier S: 500 000 po_line rows
-- Cardinality: 12 500 orders, 50 000 POs, 500 000 lines

USE bench;

-- ── Pattern A ────────────────────────────────────────────────────────────────

INSERT INTO order_a
SELECT
    number + 1                              AS order_id,
    (rand() % 10000) + 1                   AS customer_id,
    toDate('2024-01-01') + (rand() % 365)  AS order_date,
    ['EMEA','APAC','AMER','LATAM'][rand() % 4 + 1] AS region,
    ['OPEN','CLOSED','PENDING'][rand() % 3 + 1]    AS order_status,
    1                                      AS version
FROM numbers(12500);

INSERT INTO purchase_order_a
SELECT
    number + 1                                            AS po_id,
    (number % 12500) + 1                                  AS order_id,
    (rand() % 500) + 1                                    AS vendor_id,
    round(100 + rand() % 9900, 2)                         AS po_total,
    toDate('2024-01-01') + (rand() % 365)                 AS po_date,
    ['ISSUED','RECEIVED','PARTIAL','CANCELLED'][rand() % 4 + 1] AS po_status,
    1                                                     AS version
FROM numbers(50000);

INSERT INTO po_line_a
SELECT
    (number % 50000) + 1                            AS po_id,
    (number % 10) + 1                               AS line_id,
    ((number % 50000) % 12500) + 1                  AS order_id,
    (rand() % 1000) + 1                             AS product_id,
    (rand() % 100) + 1                              AS quantity,
    round(1 + rand() % 999, 2)                      AS unit_price,
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2) AS line_amount,
    toDate('2024-01-01') + (rand() % 365)           AS line_date,
    1                                               AS version
FROM numbers(500000);

-- ── Pattern B ────────────────────────────────────────────────────────────────

INSERT INTO order_b
SELECT order_id, customer_id, order_date, region, order_status, version
FROM order_a;

-- Build one row per PO with all its lines packed into arrays
INSERT INTO purchase_order_b
SELECT
    po_id,
    any(order_id)                  AS order_id,
    any(vendor_id)                 AS vendor_id,
    any(po_total)                  AS po_total,
    any(po_date)                   AS po_date,
    any(po_status)                 AS po_status,
    groupArray(line_id)            AS `lines.line_id`,
    groupArray(product_id)         AS `lines.product_id`,
    groupArray(quantity)           AS `lines.quantity`,
    groupArray(unit_price)         AS `lines.unit_price`,
    groupArray(line_amount)        AS `lines.line_amount`
FROM (
    SELECT
        po_id, order_id, vendor_id, po_total, po_date, po_status,
        line_id, product_id, quantity, unit_price, line_amount
    FROM po_line_a
    JOIN purchase_order_a USING (po_id)
    ORDER BY po_id, line_id
)
GROUP BY po_id;

-- ── Pattern C ────────────────────────────────────────────────────────────────

INSERT INTO po_flat_c
SELECT
    l.po_id,
    l.line_id,
    l.order_id,
    p.vendor_id,
    p.po_total,
    p.po_date,
    p.po_status,
    o.customer_id,
    o.order_date,
    o.region,
    l.product_id,
    l.quantity,
    l.unit_price,
    l.line_amount,
    if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0) AS is_first_line
FROM po_line_a AS l
JOIN purchase_order_a AS p ON l.po_id = p.po_id
JOIN order_a          AS o ON l.order_id = o.order_id;
