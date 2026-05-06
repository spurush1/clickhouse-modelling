-- 16_queries_c_nn.sql  Pattern C  1:N:N benchmark queries
-- Uses TWO flags: is_first_line_of_po / is_first_line_of_order
-- Tags: /* nn:QN:C:TIER */

USE bench;

-- Q1: Total PO spend by vendor (last 30 days) — PO grain
-- Guard: is_first_line_of_po = 1  (one row per PO, 10% of table)
SELECT /* nn:Q1:C:TIER */
    vendor_id,
    countIf(is_first_line_of_po = 1)         AS po_count,
    sumIf(po_total, is_first_line_of_po = 1) AS total_po_spend
FROM po_flat_c_nn
WHERE po_date >= today() - 30
GROUP BY vendor_id ORDER BY total_po_spend DESC LIMIT 20;

-- Q2: Revenue by product_id — Line grain (always safe to SUM directly)
SELECT /* nn:Q2:C:TIER */
    product_id,
    sum(line_amount) AS revenue,
    sum(quantity)    AS units
FROM po_flat_c_nn
GROUP BY product_id ORDER BY revenue DESC LIMIT 20;

-- Q3: Orders containing product_id = 42 — Cross-grain (direct DISTINCT, single table)
SELECT /* nn:Q3:C:TIER */
    count(DISTINCT order_id) AS order_count
FROM po_flat_c_nn
WHERE product_id = 42;

-- Q4: Top 10 vendors by order count — Cross-grain (PO→order)
-- count(DISTINCT order_id) correct; use is_first_line_of_po for po_total
SELECT /* nn:Q4:C:TIER */
    vendor_id,
    count(DISTINCT order_id)                 AS order_count,
    sumIf(po_total, is_first_line_of_po = 1) AS total_po_value
FROM po_flat_c_nn
GROUP BY vendor_id ORDER BY order_count DESC LIMIT 10;

-- Q5: Monthly line-amount trend by vendor+region — single table, no join
SELECT /* nn:Q5:C:TIER */
    toStartOfMonth(po_date) AS month,
    vendor_id,
    sum(line_amount)        AS monthly_revenue
FROM po_flat_c_nn
GROUP BY month, vendor_id ORDER BY month, monthly_revenue DESC LIMIT 100;

-- Q6: Total order value by region — Order grain (NEW)
-- Guard: is_first_line_of_order = 1  (one row per order, 2.5% of table)
SELECT /* nn:Q6:C:TIER */
    region,
    countIf(is_first_line_of_order = 1)              AS order_count,
    sumIf(order_total, is_first_line_of_order = 1)   AS total_order_value
FROM po_flat_c_nn
GROUP BY region ORDER BY total_order_value DESC;

-- Q7: PO spend vs line spend variance by vendor — Cross-all-grains (NEW)
-- Committed: sum po_total once per PO via is_first_line_of_po
-- Actual: sum line_amount always (line grain, always safe)
SELECT /* nn:Q7:C:TIER */
    vendor_id,
    sumIf(po_total,    is_first_line_of_po = 1) AS committed_po_spend,
    sum(line_amount)                            AS actual_line_spend,
    committed_po_spend - actual_line_spend      AS variance
FROM po_flat_c_nn
GROUP BY vendor_id ORDER BY abs(variance) DESC LIMIT 20;
