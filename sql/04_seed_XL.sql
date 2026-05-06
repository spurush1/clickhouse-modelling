-- 04_seed_XL.sql
-- Seed tier XL: 100 000 000 po_line rows
-- Cardinality: 2 500 000 orders, 10 000 000 POs, 100 000 000 lines
-- Estimated run time: 15-25 minutes on i7-12700H with 24 GB RAM limit

USE bench;

-- Insert in batches of 1M to avoid excessive memory during generation
INSERT INTO order_a
SELECT
    number + 1                              AS order_id,
    (rand() % 200000) + 1                  AS customer_id,
    toDate('2022-01-01') + (rand() % 1095) AS order_date,
    ['EMEA','APAC','AMER','LATAM'][rand() % 4 + 1] AS region,
    ['OPEN','CLOSED','PENDING'][rand() % 3 + 1]    AS order_status,
    1                                      AS version
FROM numbers(2500000);

INSERT INTO purchase_order_a
SELECT
    number + 1                                            AS po_id,
    (number % 2500000) + 1                                AS order_id,
    (rand() % 500) + 1                                    AS vendor_id,
    round(100 + rand() % 9900, 2)                         AS po_total,
    toDate('2022-01-01') + (rand() % 1095)                AS po_date,
    ['ISSUED','RECEIVED','PARTIAL','CANCELLED'][rand() % 4 + 1] AS po_status,
    1                                                     AS version
FROM numbers(10000000);

-- Insert lines in 10 batches of 10M to keep memory manageable
INSERT INTO po_line_a
SELECT
    (number % 10000000) + 1                         AS po_id,
    (number % 10) + 1                               AS line_id,
    ((number % 10000000) % 2500000) + 1             AS order_id,
    (rand() % 1000) + 1                             AS product_id,
    (rand() % 100) + 1                              AS quantity,
    round(1 + rand() % 999, 2)                      AS unit_price,
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2) AS line_amount,
    toDate('2022-01-01') + (rand() % 1095)          AS line_date,
    1                                               AS version
FROM numbers(100000000);

INSERT INTO order_b SELECT order_id, customer_id, order_date, region, order_status, version FROM order_a;

INSERT INTO purchase_order_b
SELECT
    po_id, any(order_id), any(vendor_id), any(po_total), any(po_date), any(po_status),
    groupArray(line_id), groupArray(product_id), groupArray(quantity),
    groupArray(unit_price), groupArray(line_amount)
FROM (
    SELECT p.po_id, p.order_id, p.vendor_id, p.po_total, p.po_date, p.po_status,
           l.line_id, l.product_id, l.quantity, l.unit_price, l.line_amount
    FROM po_line_a l JOIN purchase_order_a p USING (po_id) ORDER BY po_id, line_id
)
GROUP BY po_id
SETTINGS max_memory_usage = 20000000000;

INSERT INTO po_flat_c
SELECT l.po_id, l.line_id, l.order_id, p.vendor_id, p.po_total, p.po_date, p.po_status,
       o.customer_id, o.order_date, o.region,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0)
FROM po_line_a l
JOIN purchase_order_a p ON l.po_id = p.po_id
JOIN order_a          o ON l.order_id = o.order_id
SETTINGS max_memory_usage = 20000000000;
