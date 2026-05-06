-- 15_queries_b_nn.sql  Pattern B  1:N:N benchmark queries
-- Tags: /* nn:QN:B:TIER */

USE bench;

-- Q1: Total PO spend by vendor (last 30 days) — PO grain (naturally correct, no ARRAY JOIN)
SELECT /* nn:Q1:B:TIER */
    vendor_id,
    count()        AS po_count,
    sum(po_total)  AS total_po_spend
FROM purchase_order_b_nn
WHERE po_date >= today() - 30
GROUP BY vendor_id ORDER BY total_po_spend DESC LIMIT 20;

-- Q2: Revenue by product_id — Line grain (requires ARRAY JOIN)
SELECT /* nn:Q2:B:TIER */
    lines.product_id     AS product_id,
    sum(lines.line_amount) AS revenue,
    sum(lines.quantity)    AS units
FROM purchase_order_b_nn ARRAY JOIN lines
GROUP BY product_id ORDER BY revenue DESC LIMIT 20;

-- Q3: Orders containing product_id = 42 — Cross-grain via has()
SELECT /* nn:Q3:B:TIER */
    count(DISTINCT order_id) AS order_count
FROM purchase_order_b_nn
WHERE has(`lines.product_id`, 42);

-- Q4: Top 10 vendors by order count — PO grain
SELECT /* nn:Q4:B:TIER */
    vendor_id,
    count(DISTINCT order_id) AS order_count,
    sum(po_total)            AS total_po_value
FROM purchase_order_b_nn
GROUP BY vendor_id ORDER BY order_count DESC LIMIT 10;

-- Q5: Monthly line-amount trend by vendor — Line+time (ARRAY JOIN)
SELECT /* nn:Q5:B:TIER */
    toStartOfMonth(po_date) AS month,
    vendor_id,
    sum(lines.line_amount)  AS monthly_revenue
FROM purchase_order_b_nn ARRAY JOIN lines
GROUP BY month, vendor_id ORDER BY month, monthly_revenue DESC LIMIT 100;

-- Q6: Total order value by region — Order grain (join to order_b_nn required)
SELECT /* nn:Q6:B:TIER */
    o.region,
    count(DISTINCT p.order_id)  AS order_count,
    sum(o.order_total)          AS total_order_value
FROM purchase_order_b_nn AS p
JOIN order_b_nn AS o ON p.order_id = o.order_id
GROUP BY o.region ORDER BY total_order_value DESC;

-- Q7: PO spend vs line spend variance by vendor — Cross-all-grains
SELECT /* nn:Q7:B:TIER */
    vendor_id,
    sum(po_total)                            AS committed_po_spend,
    sum(arraySum(`lines.line_amount`))       AS actual_line_spend,
    committed_po_spend - actual_line_spend   AS variance
FROM purchase_order_b_nn
GROUP BY vendor_id ORDER BY abs(variance) DESC LIMIT 20;
