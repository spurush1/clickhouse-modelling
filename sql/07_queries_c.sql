-- 07_queries_c.sql
-- Pattern C benchmark queries — Flat denormalized line-grain table
-- Double-counting handled via is_first_line = 1 marker for header-level metrics
-- Tags: /* bench:QN:C:TIER */

USE bench;

-- ── Q1: Total spend by vendor (last 30 days) — Header grain ─────────────────
-- MUST filter is_first_line = 1 to avoid double-counting po_total

SELECT /* bench:Q1:C:TIER */
    vendor_id,
    countIf(is_first_line = 1)          AS po_count,
    sumIf(po_total, is_first_line = 1)  AS total_spend
FROM po_flat_c
WHERE po_date >= today() - 30
GROUP BY vendor_id
ORDER BY total_spend DESC
LIMIT 20;

-- ── Q2: Revenue by product_id — Line grain ───────────────────────────────────
-- line_amount is safe to sum directly — no double-counting risk

SELECT /* bench:Q2:C:TIER */
    product_id,
    sum(line_amount) AS revenue,
    sum(quantity)    AS units_sold
FROM po_flat_c
GROUP BY product_id
ORDER BY revenue DESC
LIMIT 20;

-- ── Q3: Count orders containing product_id = 42 — Cross-grain ───────────────

SELECT /* bench:Q3:C:TIER */
    count(DISTINCT order_id) AS order_count
FROM po_flat_c
WHERE product_id = 42;

-- ── Q4: Top 10 vendors by order count — Header grain ────────────────────────
-- count(DISTINCT order_id) is correct but expensive; is_first_line shortcut cheaper

SELECT /* bench:Q4:C:TIER */
    vendor_id,
    count(DISTINCT order_id)            AS order_count,
    sumIf(po_total, is_first_line = 1)  AS total_po_value
FROM po_flat_c
GROUP BY vendor_id
ORDER BY order_count DESC
LIMIT 10;

-- ── Q5: Monthly line-amount trend by vendor — Line + time ───────────────────

SELECT /* bench:Q5:C:TIER */
    toStartOfMonth(po_date) AS month,
    vendor_id,
    sum(line_amount)        AS monthly_revenue
FROM po_flat_c
GROUP BY month, vendor_id
ORDER BY month, monthly_revenue DESC
LIMIT 100;
