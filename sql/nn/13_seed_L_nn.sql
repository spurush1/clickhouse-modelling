-- 13_seed_L_nn.sql
-- 1:N:N Tier L: 10 000 000 po_line rows
-- Cardinality: 250 000 orders × 4 POs × 10 lines

USE bench;

INSERT INTO order_a_nn
SELECT
    number + 1,
    (rand() % 50000) + 1,
    toDate('2023-01-01') + (rand() % 730),
    ['EMEA','APAC','AMER','LATAM'][rand() % 4 + 1],
    ['OPEN','CLOSED','PENDING'][rand() % 3 + 1],
    round(1000 + rand() % 49000, 2),
    1
FROM numbers(250000);

INSERT INTO purchase_order_a_nn
SELECT
    number + 1,
    intDiv(number, 4) + 1,
    (rand() % 500) + 1,
    round(100 + rand() % 9900, 2),
    toDate('2023-01-01') + (rand() % 730),
    ['ISSUED','RECEIVED','PARTIAL','CANCELLED'][rand() % 4 + 1],
    1
FROM numbers(1000000);

INSERT INTO po_line_a_nn
SELECT
    intDiv(number, 10) + 1,
    (number % 10) + 1,
    intDiv(intDiv(number, 10), 4) + 1,
    (rand() % 1000) + 1,
    (rand() % 100) + 1,
    round(1 + rand() % 999, 2),
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2),
    toDate('2023-01-01') + (rand() % 730),
    1
FROM numbers(10000000);

INSERT INTO order_b_nn
SELECT order_id, customer_id, order_date, region, order_status, order_total, version
FROM order_a_nn;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id,
    any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date),  any(sub_po_status),
    groupArray(sub_line_id),   groupArray(sub_product_id),
    groupArray(sub_quantity),  groupArray(sub_unit_price),
    groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    ORDER BY l.po_id, l.line_id
) GROUP BY sub_po_id;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l
JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn           AS o ON p.order_id = o.order_id;
