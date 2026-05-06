-- 13_seed_XL_nn.sql
-- 1:N:N Tier XL: 100 000 000 po_line rows
-- Cardinality: 2 500 000 orders × 4 POs × 10 lines

USE bench;

INSERT INTO order_a_nn
SELECT
    number + 1,
    (rand() % 200000) + 1,
    toDate('2022-01-01') + (rand() % 1095),
    ['EMEA','APAC','AMER','LATAM'][rand() % 4 + 1],
    ['OPEN','CLOSED','PENDING'][rand() % 3 + 1],
    round(1000 + rand() % 49000, 2),
    1
FROM numbers(2500000);

INSERT INTO purchase_order_a_nn
SELECT
    number + 1,
    intDiv(number, 4) + 1,
    (rand() % 500) + 1,
    round(100 + rand() % 9900, 2),
    toDate('2022-01-01') + (rand() % 1095),
    ['ISSUED','RECEIVED','PARTIAL','CANCELLED'][rand() % 4 + 1],
    1
FROM numbers(10000000);

INSERT INTO po_line_a_nn
SELECT
    intDiv(number, 10) + 1,
    (number % 10) + 1,
    intDiv(intDiv(number, 10), 4) + 1,
    (rand() % 1000) + 1,
    (rand() % 100) + 1,
    round(1 + rand() % 999, 2),
    round(((rand() % 100) + 1) * (1 + rand() % 999), 2),
    toDate('2022-01-01') + (rand() % 1095),
    1
FROM numbers(100000000);

INSERT INTO order_b_nn
SELECT order_id, customer_id, order_date, region, order_status, order_total, version
FROM order_a_nn;

-- Pattern B: batch in 10 × 1M POs to avoid OOM (same as 1:N benchmark finding)
INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 1 AND 1000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 1000001 AND 2000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 2000001 AND 3000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 3000001 AND 4000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 4000001 AND 5000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 5000001 AND 6000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 6000001 AND 7000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 7000001 AND 8000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 8000001 AND 9000000)
GROUP BY sub_po_id;

INSERT INTO purchase_order_b_nn
SELECT sub_po_id, any(sub_order_id), any(sub_vendor_id), any(sub_po_total),
    any(sub_po_date), any(sub_po_status),
    groupArray(sub_line_id), groupArray(sub_product_id), groupArray(sub_quantity),
    groupArray(sub_unit_price), groupArray(sub_line_amount)
FROM (SELECT l.po_id AS sub_po_id, p.order_id AS sub_order_id, p.vendor_id AS sub_vendor_id,
           p.po_total AS sub_po_total, p.po_date AS sub_po_date, p.po_status AS sub_po_status,
           l.line_id AS sub_line_id, l.product_id AS sub_product_id, l.quantity AS sub_quantity,
           l.unit_price AS sub_unit_price, l.line_amount AS sub_line_amount
    FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    WHERE l.po_id BETWEEN 9000001 AND 10000000)
GROUP BY sub_po_id;

-- Pattern C: insert in 10 batches of 1M POs to avoid OOM at 100M lines
-- The window functions (PARTITION BY po_id and order_id) are self-contained per batch
-- because po_id ranges don't overlap, and each order's POs fall within the same batch
-- (order 1 has po_ids 1-4, order 2 has po_ids 5-8, etc. — contiguous blocks)
INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 1 AND 1000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 1000001 AND 2000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 2000001 AND 3000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 3000001 AND 4000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 4000001 AND 5000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 5000001 AND 6000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 6000001 AND 7000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 7000001 AND 8000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 8000001 AND 9000000;

INSERT INTO po_flat_c_nn
SELECT l.po_id, l.line_id, o.order_id, o.customer_id, o.order_date, o.region, o.order_status,
       o.order_total, p.vendor_id, p.po_date, p.po_status, p.po_total,
       l.product_id, l.quantity, l.unit_price, l.line_amount,
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0),
       if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
          AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
FROM po_line_a_nn AS l JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
JOIN order_a_nn AS o ON p.order_id = o.order_id WHERE l.po_id BETWEEN 9000001 AND 10000000;
