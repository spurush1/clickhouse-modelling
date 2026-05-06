-- 14_queries_a_nn.sql  Pattern A  1:N:N benchmark queries
-- Tags: /* nn:QN:A:TIER */

USE bench;

-- Q1: Total PO spend by vendor (last 30 days) — PO grain
SELECT /* nn:Q1:A:TIER */
    vendor_id,
    count()        AS po_count,
    sum(po_total)  AS total_po_spend
FROM purchase_order_a_nn FINAL
WHERE po_date >= today() - 30
GROUP BY vendor_id
ORDER BY total_po_spend DESC LIMIT 20;

-- Q2: Revenue by product_id — Line grain
SELECT /* nn:Q2:A:TIER */
    product_id,
    sum(line_amount) AS revenue,
    sum(quantity)    AS units
FROM po_line_a_nn FINAL
GROUP BY product_id ORDER BY revenue DESC LIMIT 20;

-- Q3: Orders containing product_id = 42 — Cross-grain (line→order)
SELECT /* nn:Q3:A:TIER */
    count(DISTINCT order_id) AS order_count
FROM po_line_a_nn FINAL
WHERE product_id = 42;

-- Q4: Top 10 vendors by order count — Cross-grain (PO→order via po→order_id)
SELECT /* nn:Q4:A:TIER */
    p.vendor_id,
    count(DISTINCT p.order_id) AS order_count,
    sum(p.po_total)            AS total_po_value
FROM purchase_order_a_nn AS p FINAL
GROUP BY p.vendor_id
ORDER BY order_count DESC LIMIT 10;

-- Q5: Monthly line-amount trend by vendor+region — Line+time+join
SELECT /* nn:Q5:A:TIER */
    toStartOfMonth(l.line_date)                                       AS month,
    dictGet('bench.order_dict_nn', 'region', toUInt64(l.order_id))   AS region,
    p.vendor_id,
    sum(l.line_amount) AS monthly_revenue
FROM po_line_a_nn AS l FINAL
JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
GROUP BY month, region, p.vendor_id
ORDER BY month, monthly_revenue DESC LIMIT 100
SETTINGS join_algorithm = 'full_sorting_merge';

-- Q6: Total order value by region — Order grain
-- dictGet retrieves region; query order_a_nn FINAL directly for order_total
SELECT /* nn:Q6:A:TIER */
    region,
    count()        AS order_count,
    sum(order_total) AS total_order_value
FROM order_a_nn FINAL
GROUP BY region
ORDER BY total_order_value DESC;

-- Q7: PO spend vs line spend variance by vendor — Cross-all-grains
-- Committed from purchase_order_a_nn; actual from po_line_a_nn; join on vendor_id subquery
SELECT /* nn:Q7:A:TIER */
    po.vendor_id,
    po.committed_po_spend,
    li.actual_line_spend,
    po.committed_po_spend - li.actual_line_spend AS variance
FROM (
    SELECT vendor_id, sum(po_total) AS committed_po_spend
    FROM purchase_order_a_nn FINAL
    GROUP BY vendor_id
) AS po
JOIN (
    SELECT p.vendor_id, sum(l.line_amount) AS actual_line_spend
    FROM po_line_a_nn AS l FINAL
    JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
    GROUP BY p.vendor_id
    SETTINGS join_algorithm = 'full_sorting_merge'
) AS li ON po.vendor_id = li.vendor_id
ORDER BY abs(variance) DESC LIMIT 20;
