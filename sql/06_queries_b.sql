-- 06_queries_b.sql
-- Pattern B benchmark queries — Nested arrays with ARRAY JOIN
-- Tags: /* bench:QN:B:TIER */

USE bench;

-- ── Q1: Total spend by vendor (last 30 days) — Header grain ─────────────────
-- Naturally correct — po_total is a scalar column on the PO row (no array)

SELECT /* bench:Q1:B:TIER */
    vendor_id,
    count()          AS po_count,
    sum(po_total)    AS total_spend
FROM purchase_order_b
WHERE po_date >= today() - 30
GROUP BY vendor_id
ORDER BY total_spend DESC
LIMIT 20;

-- ── Q2: Revenue by product_id — Line grain ───────────────────────────────────

SELECT /* bench:Q2:B:TIER */
    lines.product_id AS product_id,
    sum(lines.line_amount) AS revenue,
    sum(lines.quantity)    AS units_sold
FROM purchase_order_b
ARRAY JOIN lines
GROUP BY product_id
ORDER BY revenue DESC
LIMIT 20;

-- ── Q3: Count orders containing product_id = 42 — Cross-grain ───────────────
-- has() checks array membership without a full ARRAY JOIN

SELECT /* bench:Q3:B:TIER */
    count(DISTINCT order_id) AS order_count
FROM purchase_order_b
WHERE has(`lines.product_id`, 42);

-- ── Q4: Top 10 vendors by order count — Header grain ────────────────────────

SELECT /* bench:Q4:B:TIER */
    vendor_id,
    count(DISTINCT order_id) AS order_count,
    sum(po_total)            AS total_po_value
FROM purchase_order_b
GROUP BY vendor_id
ORDER BY order_count DESC
LIMIT 10;

-- ── Q5: Monthly line-amount trend by vendor — Line + time ───────────────────

SELECT /* bench:Q5:B:TIER */
    toStartOfMonth(po_date)  AS month,
    vendor_id,
    sum(lines.line_amount)   AS monthly_revenue
FROM purchase_order_b
ARRAY JOIN lines
GROUP BY month, vendor_id
ORDER BY month, monthly_revenue DESC
LIMIT 100;
