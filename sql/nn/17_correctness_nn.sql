-- 17_correctness_nn.sql
-- Cross-pattern correctness gate for 1:N:N scenario
-- Every check must return PASS

USE bench;

-- Q1: Total PO spend (all vendors, all dates)
WITH
    a AS (SELECT round(sum(po_total), 0) AS v FROM purchase_order_a_nn FINAL),
    b AS (SELECT round(sum(po_total), 0) AS v FROM purchase_order_b_nn),
    c AS (SELECT round(sumIf(po_total, is_first_line_of_po = 1), 0) AS v FROM po_flat_c_nn)
SELECT 'Q1_po_spend' AS chk, a.v AS A, b.v AS B, c.v AS C,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result FROM a, b, c;

-- Q2: Total line revenue (all products)
WITH
    a AS (SELECT round(sum(line_amount), 0) AS v FROM po_line_a_nn FINAL),
    b AS (SELECT round(sum(lines.line_amount), 0) AS v FROM purchase_order_b_nn ARRAY JOIN lines),
    c AS (SELECT round(sum(line_amount), 0) AS v FROM po_flat_c_nn)
SELECT 'Q2_line_revenue' AS chk, a.v AS A, b.v AS B, c.v AS C,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result FROM a, b, c;

-- Q3: Order count for product_id = 42
WITH
    a AS (SELECT count(DISTINCT order_id) AS v FROM po_line_a_nn FINAL WHERE product_id = 42),
    b AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_b_nn WHERE has(`lines.product_id`, 42)),
    c AS (SELECT count(DISTINCT order_id) AS v FROM po_flat_c_nn WHERE product_id = 42)
SELECT 'Q3_order_count_p42' AS chk, a.v AS A, b.v AS B, c.v AS C,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result FROM a, b, c;

-- Q4: Total distinct orders across all vendors
WITH
    a AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_a_nn FINAL),
    b AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_b_nn),
    c AS (SELECT count(DISTINCT order_id) AS v FROM po_flat_c_nn)
SELECT 'Q4_distinct_orders' AS chk, a.v AS A, b.v AS B, c.v AS C,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result FROM a, b, c;

-- Q6: Total order value (order grain — the critical 1:N:N double-count test)
WITH
    a AS (SELECT round(sum(order_total), 0) AS v FROM order_a_nn FINAL),
    b AS (SELECT round(sum(o.order_total), 0) AS v
          FROM (SELECT DISTINCT order_id FROM purchase_order_b_nn) p
          JOIN order_b_nn AS o ON p.order_id = o.order_id),
    c AS (SELECT round(sumIf(order_total, is_first_line_of_order = 1), 0) AS v FROM po_flat_c_nn)
SELECT 'Q6_order_total' AS chk, a.v AS A, b.v AS B, c.v AS C,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result FROM a, b, c;

-- Q7: PO spend (should equal Q1 result — cross-check both guard flags)
WITH
    a AS (SELECT round(sum(po_total), 0) AS v FROM purchase_order_a_nn FINAL),
    c_po AS (SELECT round(sumIf(po_total, is_first_line_of_po = 1), 0) AS v FROM po_flat_c_nn),
    c_ord AS (SELECT round(sumIf(order_total, is_first_line_of_order = 1), 0) AS v FROM po_flat_c_nn),
    a_ord AS (SELECT round(sum(order_total), 0) AS v FROM order_a_nn FINAL)
SELECT 'Q7_both_guards' AS chk,
    a.v AS po_spend_A, c_po.v AS po_spend_C_flag,
    a_ord.v AS order_total_A, c_ord.v AS order_total_C_flag,
    if(a.v = c_po.v AND a_ord.v = c_ord.v, 'PASS', 'FAIL') AS result
FROM a, c_po, c_ord, a_ord;
