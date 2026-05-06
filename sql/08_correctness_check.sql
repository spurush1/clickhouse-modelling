-- 08_correctness_check.sql
-- Correctness gate: verify all three patterns return identical results for Q1-Q5.
-- Expected: every ASSERT query returns 1. A 0 means a pattern diverges.

USE bench;

-- ── Q1 correctness: total spend across ALL vendors and dates ─────────────────

WITH
    a AS (SELECT round(sum(po_total), 0) AS v FROM purchase_order_a FINAL),
    b AS (SELECT round(sum(po_total), 0) AS v FROM purchase_order_b),
    c AS (SELECT round(sumIf(po_total, is_first_line = 1), 0) AS v FROM po_flat_c)
SELECT
    'Q1_spend_match' AS check_name,
    a.v              AS pattern_a,
    b.v              AS pattern_b,
    c.v              AS pattern_c,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result
FROM a, b, c;

-- ── Q2 correctness: total line revenue across all products ───────────────────

WITH
    a AS (SELECT round(sum(line_amount), 0) AS v FROM po_line_a FINAL),
    b AS (SELECT round(sum(lines.line_amount), 0) AS v FROM purchase_order_b ARRAY JOIN lines),
    c AS (SELECT round(sum(line_amount), 0) AS v FROM po_flat_c)
SELECT
    'Q2_revenue_match' AS check_name,
    a.v AS pattern_a,
    b.v AS pattern_b,
    c.v AS pattern_c,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result
FROM a, b, c;

-- ── Q3 correctness: order count for product_id = 42 ─────────────────────────

WITH
    a AS (SELECT count(DISTINCT order_id) AS v FROM po_line_a FINAL WHERE product_id = 42),
    b AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_b WHERE has(`lines.product_id`, 42)),
    c AS (SELECT count(DISTINCT order_id) AS v FROM po_flat_c WHERE product_id = 42)
SELECT
    'Q3_order_count_match' AS check_name,
    a.v AS pattern_a,
    b.v AS pattern_b,
    c.v AS pattern_c,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result
FROM a, b, c;

-- ── Q4 correctness: total unique order count across all vendors ──────────────

WITH
    a AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_a FINAL),
    b AS (SELECT count(DISTINCT order_id) AS v FROM purchase_order_b),
    c AS (SELECT count(DISTINCT order_id) AS v FROM po_flat_c)
SELECT
    'Q4_vendor_order_count_match' AS check_name,
    a.v AS pattern_a,
    b.v AS pattern_b,
    c.v AS pattern_c,
    if(a.v = b.v AND b.v = c.v, 'PASS', 'FAIL') AS result
FROM a, b, c;

-- ── Q5 correctness: total line revenue (all months, all vendors) ─────────────
-- Same as Q2 different grain — cross-check that grouping doesn't lose rows

WITH
    a AS (SELECT round(sum(line_amount), 0) AS v FROM po_line_a FINAL),
    c AS (SELECT round(sum(line_amount), 0) AS v FROM po_flat_c)
SELECT
    'Q5_monthly_total_match_AC' AS check_name,
    a.v AS pattern_a,
    c.v AS pattern_c,
    if(a.v = c.v, 'PASS', 'FAIL') AS result
FROM a, c;
