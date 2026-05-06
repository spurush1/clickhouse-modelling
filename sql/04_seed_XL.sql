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
    intDiv(number, 10) + 1                          AS po_id,
    (number % 10) + 1                               AS line_id,
    (intDiv(number, 10) % 2500000) + 1              AS order_id,
    (rand() % 1000) + 1                             AS product_id,
    (rand() % 100) + 1                              AS quantity,
    round(1 + rand() % 999, 2)                      AS unit_price,
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2) AS line_amount,
    toDate('2022-01-01') + (rand() % 1095)          AS line_date,
    1                                               AS version
FROM numbers(100000000);

INSERT INTO order_b SELECT order_id, customer_id, order_date, region, order_status, version FROM order_a;

-- Insert Pattern B in 10 batches of 1M POs to stay within 16 GB memory
INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 1 AND 1000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 1000001 AND 2000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 2000001 AND 3000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 3000001 AND 4000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 4000001 AND 5000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 5000001 AND 6000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 6000001 AND 7000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 7000001 AND 8000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 8000001 AND 9000000
)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (
    SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a AS l JOIN purchase_order_a AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 9000001 AND 10000000
)
GROUP BY sub_po_id;

INSERT INTO po_flat_c
SELECT l.po_id, l.line_id, l.order_id, p.vendor_id, p.po_total, p.po_date, p.po_status,
       o.customer_id, o.order_date, o.region,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0)
FROM po_line_a l
JOIN purchase_order_a p ON l.po_id = p.po_id
JOIN order_a          o ON l.order_id = o.order_id
SETTINGS max_memory_usage = 20000000000;
