-- 05_queries_a.sql
-- Pattern A benchmark queries — run 5 times each (run 1 = warm-up)
-- Tags: /* bench:QN:A:TIER */ — replaced by run_bench.sh at execution time

USE bench;

-- ── Q1: Total spend by vendor (last 30 days) — Header grain ─────────────────
-- No double-counting risk: po_total lives in purchase_order_a (one row per PO)

SELECT /* bench:Q1:A:TIER */
    vendor_id,
    count()          AS po_count,
    sum(po_total)    AS total_spend
FROM purchase_order_a FINAL
WHERE po_date >= today() - 30
GROUP BY vendor_id
ORDER BY total_spend DESC
LIMIT 20;

-- ── Q2: Revenue by product_id — Line grain ───────────────────────────────────

SELECT /* bench:Q2:A:TIER */
    product_id,
    sum(line_amount) AS revenue,
    sum(quantity)    AS units_sold
FROM po_line_a FINAL
GROUP BY product_id
ORDER BY revenue DESC
LIMIT 20;

-- ── Q3: Count orders containing product_id = 42 — Cross-grain ───────────────
-- Uses full_sorting_merge: po_line_a ORDER BY (po_id,...) + purchase_order_a ORDER BY (order_id, po_id)
-- order_id denormalized on po_line_a → can skip middle table for the order count

SELECT /* bench:Q3:A:TIER */
    count(DISTINCT order_id) AS order_count
FROM po_line_a FINAL
WHERE product_id = 42;

-- ── Q4: Top 10 vendors by order count — Header grain ────────────────────────

SELECT /* bench:Q4:A:TIER */
    p.vendor_id,
    count(DISTINCT p.order_id) AS order_count,
    sum(p.po_total)            AS total_po_value
FROM purchase_order_a AS p FINAL
GROUP BY p.vendor_id
ORDER BY order_count DESC
LIMIT 10;

-- ── Q5: Monthly line-amount trend by vendor — Line + time ───────────────────

SELECT /* bench:Q5:A:TIER */
    toStartOfMonth(l.line_date)                                 AS month,
    dictGet('bench.order_dict', 'region', toUInt64(l.order_id)) AS region,
    p.vendor_id,
    sum(l.line_amount)                                          AS monthly_revenue
FROM po_line_a AS l FINAL
JOIN purchase_order_a AS p ON l.po_id = p.po_id
    SETTINGS join_algorithm = 'full_sorting_merge'
GROUP BY month, region, p.vendor_id
ORDER BY month, monthly_revenue DESC
LIMIT 100;
