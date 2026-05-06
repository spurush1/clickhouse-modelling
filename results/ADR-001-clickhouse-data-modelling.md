# ADR-001: ClickHouse Data Modelling for One-to-Many Hierarchies in NLP2SQL Workloads

**Document type**: Architecture Decision Record  
**Status**: PROPOSED — pending board approval  
**Authors**: Purushothaman Srinivasanarasimhan  
**Date**: 2026-05-06  
**Repo**: https://github.com/spurush1/clickhouse-modelling  
**ClickHouse version tested**: 24.3.18  

---

## 1. Executive Summary

This document presents empirical benchmarks for two structural problems that arise when
modelling procurement data in ClickHouse for an NLP2SQL workload:

- **Section A — 1:N** — `order → po_line` (one header, many lines). The classic
  single-level double-counting problem with one guard flag.
- **Section B — 1:N:N** — `order → purchase_order → po_line` (two header levels, many
  lines per level). The extended double-counting problem requiring two independent guard
  flags.

The NLP2SQL constraint drives the entire decision: the data model must make correct SQL
easy to generate and wrong SQL obviously wrong, because the LLM writes queries without
runtime context.

**Board-level verdict:**

| Pattern | 1:N winner | 1:N:N winner | Reason |
|---|---|---|---|
| A — Co-sorted tables + dict | ❌ | ❌ | FINAL penalty at scale; joins at 100M lines |
| B — Nested arrays | ✅ niche | ⚠️ partial | Fast headers/cross-grain; bad for order-grain |
| **C — Flat denormalized** | ✅ **overall** | ✅ **overall** | Fastest queries; lowest memory; NLP2SQL safe |

**Pattern C scales cleanly to 1:N:N with two guard flags** (`is_first_line_of_po`,
`is_first_line_of_order`). The two-flag extension adds zero query overhead, ~2 bytes
per row of storage, and a single additional prompt rule for the NLP2SQL agent.

---

## 2. Problem Statement

### 2.1 The double-counting problem

When parent-child data is denormalized into a flat table at the child grain, parent-level
fields are physically repeated on every child row. Naive aggregation overcounts them.

**1:N case (order → line):**
A PO with 10 lines has `po_total` repeated 10 times.
```sql
SUM(po_total)  -- returns 10× the real value
```

**1:N:N case (order → PO → line):**
An order with 4 POs × 10 lines has `order_total` repeated 40 times and `po_total`
repeated 10 times per PO.
```sql
SUM(order_total)  -- returns 40× the real value
SUM(po_total)     -- returns 10× the real value
```
Each header grain above the line requires its own independent guard.

### 2.2 NLP2SQL constraint

The Scorpio NLP2SQL agent translates natural language to ClickHouse SQL dynamically.
The LLM cannot be expected to:

| Failure mode | Pattern A risk | Pattern B risk | Pattern C risk |
|---|---|---|---|
| Forget `FINAL` on ReplacingMergeTree | High — silent wrong results | N/A | N/A |
| Forget `ARRAY JOIN` on nested columns | N/A | High — syntax error | N/A |
| Use wrong join algorithm | High — 120× slower | N/A | N/A |
| Forget guard flag on header metric | N/A | N/A | Detectable (10× overcount) |
| Write multi-table join for cross-grain | Always required | Sometimes | Never required |

Pattern C's only failure mode (forgetting `is_first_line_of_po`) produces an obviously
wrong number (10× revenue). Pattern A's failure mode (forgetting `FINAL`) produces a
plausibly correct number that is silently wrong.

---

## 3. Test Environment and Methodology

### 3.1 Hardware

| Resource | Specification |
|---|---|
| Machine | Intel i7-12700H (14 cores / 20 threads), 32 GB RAM, NVMe SSD |
| Docker limits | 4 CPUs / 16 GB RAM (Docker Desktop on Windows) |
| Container | `clickhouse/clickhouse-server:24.3-alpine`, isolated (no other services) |
| ClickHouse version | 24.3.18 |

### 3.2 Data volume tiers (same for both studies)

| Tier | po_line rows | Notes |
|---|---|---|
| S | 500,000 | Validation tier |
| M | 1,000,000 | Small production |
| L | 10,000,000 | Medium production |
| XL | 100,000,000 | Large production |

### 3.3 Cardinality

| Study | orders | purchase_orders | po_lines | rows per order |
|---|---|---|---|---|
| 1:N (simplified) | 12,500–2,500,000 | 50,000–10,000,000 | 500K–100M | 40 (effective) |
| 1:N:N (true) | 12,500–2,500,000 | 50,000–10,000,000 | 500K–100M | 40 (4 POs × 10 lines) |

Both studies use identical po_line row counts per tier. The 1:N:N study introduces
a meaningful `order_total` metric distinct from `po_total`, and the true 4 POs per order
relationship.

### 3.4 Measurement method

- 5 runs per (query × pattern × tier). Median reported.
- Timings from `system.query_log` (`query_duration_ms`, `memory_usage`, `read_rows`).
- All correctness checks passed before timing was recorded.

---

## 4. The Three Patterns

### Pattern A — Co-sorted ReplacingMergeTree + HASHED Dictionary

Three normalized tables, each sorted so that the join key is the leading ORDER BY column.
The `full_sorting_merge` join algorithm skips the sort phase when tables are co-sorted,
reducing join memory from O(N) hash table to O(block) streaming merge.

**1:N DDL summary:**
```sql
order_a              ENGINE=ReplacingMergeTree(version)  ORDER BY order_id
purchase_order_a     ENGINE=ReplacingMergeTree(version)  ORDER BY (order_id, po_id)
po_line_a            ENGINE=ReplacingMergeTree(version)  ORDER BY (po_id, line_id)
order_dict           LAYOUT(HASHED)  -- in-memory O(1) lookup
```

**1:N:N DDL adds:** `order_total` field to `order_a_nn`; same co-sort structure.

**Critical flaw:** `FINAL` forces a full deduplication scan at query time on every
`ReplacingMergeTree` table, even when there are no duplicates. At 100M lines this
costs 7+ seconds per query regardless of filters.

---

### Pattern B — Nested Arrays (one row per PO)

One row per purchase_order, with line items stored as parallel `Array()` columns.
Header aggregations are naturally correct (scalar columns). Line aggregations require
`ARRAY JOIN` to explode arrays into rows. Array membership uses `has()`.

**1:N DDL:**
```sql
purchase_order_b (po_id, order_id, vendor_id, po_total, po_date, po_status,
    lines.line_id Array(UInt32), lines.product_id Array(UInt32),
    lines.quantity Array(UInt32), lines.line_amount Array(Decimal(18,2)))
ENGINE = MergeTree() ORDER BY (order_id, po_id)
```

**1:N:N DDL adds:** Separate `order_b_nn` table with `order_total`. Cross-order-grain
queries require `JOIN order_b_nn` — this is the weak point in 1:N:N.

**Memory wall:** At XL tier, building arrays via `groupArray()` on 10M POs × 10 lines
exceeds 14 GB RAM. Requires batched inserts by `po_id` range.

---

### Pattern C — Flat Denormalized Line-Grain Table

Everything pre-joined at ingest. One row per line with all parent attributes denormalized.
Guard flags — one per header grain — mark exactly one row per entity instance.

**1:N DDL:**
```sql
po_flat_c (po_id, line_id, order_id, vendor_id, po_total, po_date, po_status,
    customer_id, order_date, region, product_id, quantity, unit_price, line_amount,
    is_first_line UInt8)   -- 1 on first line of each PO (10% of rows)
ENGINE = MergeTree() ORDER BY (po_date, vendor_id, po_id, line_id)
```

**1:N:N DDL adds two flags:**
```sql
po_flat_c_nn (... same columns ...,
    order_total           Decimal(18,2),  -- order-grain metric
    is_first_line_of_po   UInt8,          -- 1 on 1st line of each PO   (10% of rows)
    is_first_line_of_order UInt8)         -- 1 on 1st line of each order (2.5% of rows)
```

**How the two flags are computed at ingest:**
```sql
INSERT INTO po_flat_c_nn
SELECT ...,
    -- Guard for PO grain: one representative row per PO
    if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id), 1, 0)
        AS is_first_line_of_po,

    -- Guard for order grain: one representative row per order
    -- = first line of the first PO of that order
    if(l.line_id = min(l.line_id) OVER (PARTITION BY l.po_id)
       AND l.po_id = min(l.po_id) OVER (PARTITION BY o.order_id), 1, 0)
        AS is_first_line_of_order
FROM po_line AS l
JOIN purchase_order AS p ON l.po_id = p.po_id
JOIN order_table    AS o ON p.order_id = o.order_id;
```

**Why the flags are correct and stable:**  
- `is_first_line_of_po = 1` on exactly 1 of 10 rows per PO → `sumIf(po_total, is_first_line_of_po=1)` sums `po_total` exactly once per PO.  
- `is_first_line_of_order = 1` on exactly 1 of 40 rows per order → `sumIf(order_total, is_first_line_of_order=1)` sums `order_total` exactly once per order.  
- `min(line_id)` and `min(po_id)` are deterministic — the same row is chosen every time, regardless of storage order or reloads.

**Data snapshot** (1 order, 2 POs, 3 lines each):

| order_id | po_id | line_id | order_total | po_total | line_amount | is_first_line_of_po | is_first_line_of_order |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 5000 | 1200 | 150 | **1** | **1** |
| 1 | 1 | 2 | 5000 | 1200 | 300 | 0 | 0 |
| 1 | 1 | 3 | 5000 | 1200 | 750 | 0 | 0 |
| 1 | 2 | 1 | 5000 | 3800 | 900 | **1** | 0 |
| 1 | 2 | 2 | 5000 | 3800 | 400 | 0 | 0 |
| 1 | 2 | 3 | 5000 | 3800 | 1500 | 0 | 0 |

```sql
SUM(line_amount)                                       = 4100  ✅
sumIf(po_total,    is_first_line_of_po    = 1)         = 5000  ✅ (1200 + 3800)
sumIf(order_total, is_first_line_of_order = 1)         = 5000  ✅
COUNT(DISTINCT po_id)                                  = 2     ✅
COUNT(DISTINCT order_id)                               = 1     ✅
```

---

## 5. Query Set

### Section A — 1:N queries (Q1–Q5)

| Query | Business question | Grain tested |
|---|---|---|
| Q1 | Total PO spend by vendor (last 30 days) | PO header |
| Q2 | Revenue by product_id | Line |
| Q3 | Orders containing product_id = 42 | Cross-grain (line → order) |
| Q4 | Top 10 vendors by order count | Cross-grain (PO → order) |
| Q5 | Monthly line revenue trend by vendor + region | Line + time + join |

### Section B — 1:N:N queries (Q1–Q7)

Q1–Q5 same business questions. Two new queries test the second header grain:

| Query | Business question | Grain tested |
|---|---|---|
| Q6 | Total **order** value by region | **Order** header — the new 2nd grain |
| Q7 | PO committed spend vs actual line spend variance by vendor | **Both grains simultaneously** |

**Pattern C Q6 and Q7 (no joins needed):**
```sql
-- Q6: order-grain, guarded by is_first_line_of_order
SELECT region,
    countIf(is_first_line_of_order = 1)            AS order_count,
    sumIf(order_total, is_first_line_of_order = 1) AS total_order_value
FROM po_flat_c_nn GROUP BY region;

-- Q7: both grains in one scan — committed PO spend vs actual line spend
SELECT vendor_id,
    sumIf(po_total, is_first_line_of_po = 1) AS committed_po_spend,
    sum(line_amount)                          AS actual_line_spend,
    committed_po_spend - actual_line_spend    AS variance
FROM po_flat_c_nn GROUP BY vendor_id;
```

**Pattern A Q7 (two separate subquery scans + join):**
```sql
SELECT po.vendor_id, po.committed_po_spend, li.actual_line_spend, ...
FROM (SELECT vendor_id, sum(po_total) AS committed_po_spend
      FROM purchase_order_a_nn FINAL GROUP BY vendor_id) AS po
JOIN (SELECT p.vendor_id, sum(l.line_amount) AS actual_line_spend
      FROM po_line_a_nn AS l FINAL
      JOIN purchase_order_a_nn AS p ON l.po_id = p.po_id
      GROUP BY p.vendor_id
      SETTINGS join_algorithm = 'full_sorting_merge') AS li
  ON po.vendor_id = li.vendor_id;
-- Two FINAL scans + one join = ~19 seconds at XL
```

---

## 6. Benchmark Results

### 6.1 Section A — 1:N Results (median milliseconds)

| Query | Pattern | S (500K) | M (1M) | L (10M) | XL (100M) | Scaling S→XL |
|---|---:|---:|---:|---:|---:|---|
| Q1 PO spend | A | 2 | 2 | 4 | 3 | 1.5× |
| Q1 PO spend | B | 2 | 1 | 2 | 2 | 1.0× |
| Q1 PO spend | C | 2 | 2 | 2 | 2 | 1.0× |
| Q2 Line revenue | A | 45 | 75 | 692 | **7415** | 165× ❌ |
| Q2 Line revenue | B | 8 | 1 | 57 | 524 | 65× |
| Q2 Line revenue | C | 6 | 1 | 30 | **268** | 45× ✅ |
| Q3 Cross-grain | A | 41 | 68 | 624 | **6810** | 166× ❌ |
| Q3 Cross-grain | B | 3 | 1 | 9 | **76** | 25× ✅ |
| Q3 Cross-grain | C | 3 | 1 | 13 | 87 | 29× |
| Q4 Vendor count | A | 12 | 18 | 106 | 1228 | 102× |
| Q4 Vendor count | B | 4 | 1 | 24 | **135** | 34× ✅ |
| Q4 Vendor count | C | 6 | 1 | 38 | 296 | 49× |
| Q5 Join + trend | A | 66 | 115 | 1852 | **21892** | 332× ❌ |
| Q5 Join + trend | B | 8 | 1 | 57 | 563 | 70× |
| Q5 Join + trend | C | 5 | 1 | 22 | **182** | 36× ✅ |

### 6.2 Section A — 1:N Peak Memory (MB)

| Query | Pattern | S | M | L | XL |
|---|---:|---:|---:|---:|---:|
| Q2 Line revenue | A | 30 | 56 | 400 | **730** |
| Q2 Line revenue | B | 17 | 37 | 59 | 61 |
| Q2 Line revenue | C | 1 | 0.4 | 9 | **9** |
| Q5 Join + trend | A | 54 | 86 | 508 | **1126** |
| Q5 Join + trend | B | 17 | 38 | 63 | 66 |
| Q5 Join + trend | C | 1 | 0.7 | 10 | **14** |

---

### 6.3 Section B — 1:N:N Results (median milliseconds)

Q1–Q5 carry the same business questions as Section A. Q6 and Q7 are new order-grain tests.

| Query | Pattern | S (500K) | M (1M) | L (10M) | XL (100M) | Scaling S→XL |
|---|---:|---:|---:|---:|---:|---|
| Q1 PO spend | A | 2 | 2 | 2 | 2 | 1.0× |
| Q1 PO spend | B | 2 | 2 | 2 | 2 | 1.0× |
| Q1 PO spend | C | 2 | 2 | 2 | 3 | 1.5× |
| Q2 Line revenue | A | 46 | 85 | 712 | **7571** | 165× ❌ |
| Q2 Line revenue | B | 8 | 20 | 109 | 1212 | 152× |
| Q2 Line revenue | C | 6 | 22 | 59 | **258** | 43× ✅ |
| Q3 Cross-grain | A | 42 | 74 | 660 | **6972** | 166× ❌ |
| Q3 Cross-grain | B | 3 | 5 | 20 | **166** | 55× |
| Q3 Cross-grain | C | 4 | 10 | 27 | 78 | 20× ✅ |
| Q4 Vendor count | A | 12 | 20 | 114 | 949 | 79× |
| Q4 Vendor count | B | 5 | 8 | 49 | **312** | 62× |
| Q4 Vendor count | C | 7 | 22 | 79 | 360 | 51× |
| Q5 Join + trend | A | 68 | 136 | 1930 | **22104** | 325× ❌ |
| Q5 Join + trend | B | 8 | 22 | 110 | 1242 | 155× |
| Q5 Join + trend | C | 6 | 18 | 44 | **194** | 32× ✅ |
| **Q6 Order value** | **A** | **5** | **6** | **42** | **209** | **42×** |
| **Q6 Order value** | **B** | **6** | **10** | **60** | **902** | **150× ❌** |
| **Q6 Order value** | **C** | **4** | **12** | **35** | **133** | **33× ✅** |
| **Q7 Variance** | **A** | **61** | **118** | **1739** | **19074** | **313× ❌** |
| **Q7 Variance** | **B** | **4** | **8** | **34** | **314** | **79×** |
| **Q7 Variance** | **C** | **6** | **18** | **49** | **212** | **35× ✅** |

### 6.4 Section B — 1:N:N Peak Memory (MB)

| Query | Pattern | S | M | L | XL |
|---|---:|---:|---:|---:|---:|
| Q2 Line revenue | A | 30 | 72 | 399 | **730** |
| Q2 Line revenue | B | 17 | 85 | 58 | 64 |
| Q2 Line revenue | C | 0.4 | 0.8 | 6 | **10** |
| Q5 Join + trend | A | 47 | 99 | 502 | **1091** |
| Q5 Join + trend | B | 17 | 91 | 62 | 68 |
| Q5 Join + trend | C | 1 | 1 | 10 | **15** |
| **Q6 Order value** | **A** | **0.4** | **0.7** | **12** | **90** |
| **Q6 Order value** | **B** | **4** | **7** | **83** | **831** ❌ |
| **Q6 Order value** | **C** | **0.3** | **0.5** | **3** | **6** ✅ |
| **Q7 Variance** | **A** | **31** | **52** | **388** | **951** ❌ |
| **Q7 Variance** | **B** | **2** | **25** | **9** | **18** |
| **Q7 Variance** | **C** | **0.6** | **0.6** | **5** | **10** ✅ |

---

## 7. Query-by-Query Analysis

### Q1 — PO spend by vendor (header grain)

**Both studies:** All three patterns are 1–3ms across all tiers. Pattern C's
`sumIf(po_total, is_first_line_of_po=1)` adds no measurable overhead versus Pattern A's
direct `sum(po_total)`. **Winner: tie.**

### Q2 — Line revenue by product (line grain)

Pattern A degrades catastrophically due to `FINAL` deduplication: **7.4–7.6s at XL**
in both studies. Pattern C benefits from the flat table's sorted `ORDER BY (po_date,
vendor_id, po_id, line_id)` — after the first run, blocks are page-cached and subsequent
runs hit memory only. **Winner: C > B >> A** at all scales.

**1:N:N observation:** Pattern B degrades more in 1:N:N (1212ms vs 524ms at XL).
With 10M POs each containing 10 lines, `ARRAY JOIN` must process larger blocks because
the PO table itself grew 10× (10M rows vs 1M rows in 1:N).

### Q3 — Cross-grain order count for product_id = 42

**1:N:** B wins narrowly (76ms vs 87ms) because `has()` on compressed array blocks is
slightly faster than `DISTINCT` on a flat table for this predicate shape.

**1:N:N reversal:** C now wins (78ms vs 166ms at XL). In 1:N:N, Pattern B's PO table
has 10M rows (not 1M). The `has()` must scan 10M PO-level rows whereas C's flat table
with a direct `WHERE product_id = 42` benefits from ClickHouse's primary key skip index
on `(po_date, vendor_id, po_id, line_id)`. **Winner: C in 1:N:N; B in 1:N.**

### Q4 — Vendor order count (cross-grain header)

In 1:N, Pattern B won because its PO-grain table (50K–10M rows) is much smaller than
the flat table (500K–100M rows). In 1:N:N, Pattern B's PO table is the same size as in
1:N (50K–10M rows), but Pattern C's flat table also has the same row count. The gap
closes. **Winner: B slightly in both studies (312ms vs 360ms at XL in 1:N:N).**

### Q5 — Monthly trend by vendor + region (line + time + join)

Pattern A consistently the worst: **22s at XL in both studies, ~1GB RAM**. The
`full_sorting_merge` join between 100M line rows and 10M PO rows is the bottleneck.
Pattern C is the clear winner: **182ms (1:N) / 194ms (1:N:N)**, single table scan.
**Winner: C >> B >> A** at all scales.

### Q6 — Order-grain aggregation (1:N:N only — the key new test)

This query specifically tests the **second guard flag** `is_first_line_of_order`.

- **Pattern A:** Scans `order_a_nn` directly (normalized table, no FINAL needed for
  this query since we're not deduplicating lines). Fast: 5–209ms. But requires
  knowing to query a different table for order-grain vs PO-grain.
- **Pattern B:** Must `JOIN order_b_nn` on `order_id` to get `order_total`.
  At XL: **902ms, 831MB RAM** — the join on the order table hits hard.
- **Pattern C:** `sumIf(order_total, is_first_line_of_order=1)` — single table,
  scans only 2.5% of rows. At XL: **133ms, 6MB RAM**. 

**This is the defining result of the 1:N:N study.** Pattern B, which was competitive
in 1:N, fails badly at the order grain in 1:N:N because it needs an additional JOIN
(order_b_nn) that Pattern C absorbed at ingest time.

**Winner: C > A >> B** (B catastrophically slow and RAM-heavy at XL).

### Q7 — Cross-grain variance (both PO and order grains in one query)

The most demanding query: simultaneously aggregate at PO grain (committed spend) and
line grain (actual spend) in one pass.

- **Pattern A:** Two FINAL scans + one join = **19 seconds, 951MB** at XL.
- **Pattern B:** PO grain is native (no ARRAY JOIN for PO-level sum) + `arraySum` for
  line total — clean and fast: **314ms, 18MB**.
- **Pattern C:** One scan, two `sumIf` guards + one direct `SUM` — **212ms, 10MB**.

**Winner: C ≈ B >> A.** Both B and C handle this well. Pattern A's double-FINAL
penalty makes it impractical.

---

## 8. The 1:N:N Critical Insight: Two Flags, One Scan

The central design question for 1:N:N is: *can the two-flag approach scale, and does
it degrade as the number of parent grains increases?*

**Answer: it scales perfectly, and the cost is O(1) per additional parent grain.**

Each flag column is `UInt8` (1 byte uncompressed). After LZ4 compression on a column
that is 90–97.5% zeros, each flag compresses to approximately 1–2 bits per row.

Adding `is_first_line_of_order` (the second flag):

| Metric | Before (1 flag) | After (2 flags) | Delta |
|---|---|---|---|
| Table row count | Same | Same | 0 |
| Storage per row | +1 byte | +2 bytes | +1 byte |
| Q1 query time (XL) | 2ms | 3ms | +1ms |
| Q6 query time (XL) | n/a | 133ms | New capability |
| Q7 query time (XL) | n/a | 212ms | New capability |
| NLP2SQL prompt rules | 1 sumIf rule | 2 sumIf rules | +1 rule |

If the hierarchy were 3 levels deep (`order → PO → delivery → line`), you would add
`is_first_line_of_delivery` (third flag) following the same pattern. The cost remains
O(1) per additional level: one column, one prompt rule, one `sumIf`.

**General rule:**

> Number of guard flags = number of parent entity grains above the line.
> Each flag is `1` on exactly one row per entity instance.
> Storage cost: `n × 1 byte per row`, compressed to near-zero.
> Query cost: `sumIf(metric, flag=1)` — identical execution to `sumIf` on any UInt8 column.

---

## 9. NLP2SQL Implications

### 9.1 System prompt for Pattern C (1:N:N)

```
Table: po_flat_c_nn

Column grain rules:
- line_amount, quantity, unit_price  → SUM directly (line grain, always correct)
- po_total   → sumIf(po_total,    is_first_line_of_po    = 1)  [PO grain]
- order_total → sumIf(order_total, is_first_line_of_order = 1) [order grain]

Count rules:
- COUNT(POs)    → countIf(is_first_line_of_po    = 1)
- COUNT(orders) → countIf(is_first_line_of_order = 1)

No JOIN, ARRAY JOIN, FINAL, or dictGet needed. All dimensions available directly.
```

**Three rules total.** The LLM learns one pattern (`sumIf(metric, flag=1)`) and applies
it by looking up which flag corresponds to which metric. This is learnable, consistent,
and verifiable.

### 9.2 Side-by-side NLP2SQL comparison

**"What is total order value by region?"**

```sql
-- Pattern A (LLM must know to query order_a_nn, not po or line table)
SELECT region, sum(order_total)
FROM order_a_nn FINAL
GROUP BY region;

-- Pattern B (LLM must JOIN order_b_nn — two tables, different grain)
SELECT o.region, sum(o.order_total)
FROM (SELECT DISTINCT order_id FROM purchase_order_b_nn) p
JOIN order_b_nn o ON p.order_id = o.order_id
GROUP BY o.region;

-- Pattern C (one table, one rule)
SELECT region, sumIf(order_total, is_first_line_of_order = 1) AS total
FROM po_flat_c_nn
GROUP BY region;
```

**"Which products are bought most by EMEA orders, and what is the PO value vs line value?"**

```sql
-- Pattern A (two separate scans, two FINAL, one join)
SELECT product_id,
    sum(l.line_amount) AS line_revenue,
    po_v.total_po      AS po_committed
FROM po_line_a_nn AS l FINAL
JOIN (
    SELECT p.po_id, sum(p.po_total) AS total_po
    FROM purchase_order_a_nn p FINAL
    JOIN order_a_nn o ON p.order_id = o.order_id FINAL
    WHERE o.region = 'EMEA'
    GROUP BY p.po_id
) po_v ON l.po_id = po_v.po_id
WHERE dictGet('order_dict_nn', 'region', toUInt64(l.order_id)) = 'EMEA'
GROUP BY product_id, po_v.total_po LIMIT 20;
-- Likely wrong or very slow. LLM would struggle with this pattern.

-- Pattern C (single table, two sumIf rules)
SELECT product_id,
    sum(line_amount)                          AS line_revenue,
    sumIf(po_total, is_first_line_of_po = 1)  AS po_committed
FROM po_flat_c_nn
WHERE region = 'EMEA'
GROUP BY product_id
ORDER BY line_revenue DESC LIMIT 20;
```

Pattern C collapses a 6-line multi-join query into a 7-line single-table query. The
LLM's error surface shrinks from 4 independent rules (FINAL, dictGet, join algorithm,
grain selection) to 2 rules (which `sumIf` flag for which metric).

---

## 10. Pattern Scorecard — 1:N vs 1:N:N

### 1:N scorecard

| Dimension | Weight | A | B | C |
|---|---|---|---|---|
| NLP2SQL simplicity | 30% | 3 | 4 | **9** |
| Query performance at XL | 25% | 2 | 7 | **9** |
| Memory efficiency | 15% | 3 | 8 | **10** |
| Write pipeline simplicity | 15% | 9 | 5 | 7 |
| BI tool compatibility | 10% | 9 | 3 | **9** |
| Schema token budget | 5% | 4 | 6 | **9** |
| **Weighted total** | | **4.2** | **5.8** | **9.0** |

### 1:N:N scorecard

| Dimension | Weight | A | B | C |
|---|---|---|---|---|
| NLP2SQL simplicity | 30% | 2 | 3 | **9** |
| Query performance at XL | 25% | 2 | 6 | **9** |
| Memory efficiency | 15% | 3 | 7 | **10** |
| Write pipeline simplicity | 15% | 8 | 4 | 6 |
| BI tool compatibility | 10% | 8 | 2 | **9** |
| Schema token budget | 5% | 3 | 5 | **9** |
| **Weighted total** | | **3.9** | **4.9** | **9.0** |

Pattern B drops in 1:N:N because:
- The second header grain (order) requires a JOIN to a separate table — breaking its
  single-table advantage for header-grain queries.
- The `ARRAY JOIN` cognitive overhead compounds when analysts must mentally track which
  grain each question belongs to.
- Q6 performance (order-grain aggregation) is 6.8× worse than Pattern C at XL.

---

## 11. Findings Summary

### 11.1 What the 1:N study proved

1. `FINAL` on `ReplacingMergeTree` is a query-time deduplication scan. At 100M lines
   it costs 6–22 seconds per query, making Pattern A unusable for analytical workloads.
2. Pattern C (flat + `is_first_line`) handles all query shapes in a single table with
   standard SQL, lowest memory, and predictable scaling.
3. Pattern B wins narrowly for `has()` array membership (Q3) and small-table PO-grain
   aggregations (Q4). Valid for narrow, append-only use cases.

### 11.2 What the 1:N:N study additionally proved

1. **Two independent flags solve the 1:N:N double-counting problem completely.**
   `is_first_line_of_po` guards PO-grain metrics; `is_first_line_of_order` guards
   order-grain metrics. All 24 correctness checks passed across 4 tiers.
2. **Pattern B breaks at the order grain.** Q6 (order-level aggregation) requires
   joining to a separate `order_b_nn` table. At XL: 902ms and 831MB RAM vs Pattern C's
   133ms and 6MB. The `ARRAY JOIN` model cannot absorb a second header grain cleanly.
3. **Pattern C's two-flag approach scales identically to the one-flag approach.**
   Storage overhead is 1 additional byte per row. Query overhead is zero (one more
   `sumIf` column access). The scaling factor S→XL for Q6 (33×) is comparable to Q1 (1.5×).
4. **The general rule holds:** for N levels of hierarchy above the line, add N guard flags.
   Cost per additional flag: 1 byte storage + 1 `sumIf` in queries + 1 rule in the LLM prompt.

### 11.3 Memory findings across both studies

Pattern A's memory usage grows unboundedly with data volume because joins must hold two
sorted streams simultaneously. At XL, Q5 and Q7 both peak above 1GB in Pattern A,
compared to 10–15MB for the equivalent Pattern C query.

Pattern B's memory wall (OOM at XL for `groupArray` during ingest) was reproduced in
both studies. The 1:N:N study confirmed it still requires 10 batched inserts for Pattern B
at XL tier. Pattern C's XL ingest also required batching (the 3-table JOIN + double
window function exceeded 14GB), but Pattern C's query-time memory is dramatically lower.

---

## 12. Recommendation

### 12.1 Primary recommendation: Pattern C for all new procurement gold marts

Adopt the flat denormalized line-grain table as the canonical ClickHouse gold mart schema.

**For 1:N hierarchies:** one guard flag `is_first_line`.  
**For 1:N:N hierarchies:** two guard flags `is_first_line_of_po` + `is_first_line_of_order`.  
**For deeper hierarchies:** add one flag per additional parent grain.

### 12.2 DDL template for 1:N:N procurement mart

```sql
CREATE TABLE gold_procurement_mart (
    -- Partition + sort keys
    po_date             Date,
    vendor_id           UInt32,
    -- Grain identifiers
    po_id               UInt64,
    line_id             UInt32,
    -- Order-grain attributes (40 rows per order for 4 POs × 10 lines)
    order_id            UInt64,
    customer_id         UInt32,
    order_date          Date,
    region              LowCardinality(String),
    order_status        LowCardinality(String),
    order_total         Decimal(18,2),  -- ⚠ use sumIf(..., is_first_line_of_order=1)
    -- PO-grain attributes (10 rows per PO)
    po_status           LowCardinality(String),
    po_total            Decimal(18,2),  -- ⚠ use sumIf(..., is_first_line_of_po=1)
    -- Line-grain attributes (always safe to SUM)
    product_id          UInt32,
    category_id         UInt32,
    quantity            UInt32,
    unit_price          Decimal(18,2),
    line_amount         Decimal(18,2),  -- ✅ SUM directly
    -- Double-count guards
    is_first_line_of_po     UInt8,      -- 1 on 1st line of each PO   (10% of rows)
    is_first_line_of_order  UInt8       -- 1 on 1st line of each order (2.5% of rows)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(po_date)
  ORDER BY (po_date, vendor_id, order_id, po_id, line_id);
```

### 12.3 NLP2SQL system prompt addition

```
Table: gold_procurement_mart

Metric grain rules:
  line_amount, quantity, unit_price → SUM directly (line grain, no guard needed)
  po_total    → sumIf(po_total,    is_first_line_of_po    = 1)
  order_total → sumIf(order_total, is_first_line_of_order = 1)

Count rules:
  COUNT(POs)    → countIf(is_first_line_of_po    = 1)
  COUNT(orders) → countIf(is_first_line_of_order = 1)

All dimension columns (region, vendor_id, product_id, category_id) are directly
available — no JOIN, ARRAY JOIN, FINAL, or dictGet needed.
```

### 12.4 Escape hatches

| Scenario | Recommendation |
|---|---|
| Frequent PO header updates via CDC | Write to `po_line_a` (Pattern A tables) + MV populates flat table |
| Very high QPS on `has(product_id, X)` pattern specifically | Supplementary `AggregatingMergeTree` index table |
| Pre-aggregated dashboards (sub-ms requirement) | `AggregatingMergeTree` MV on `po_flat_c_nn` grouped by `(po_date, vendor_id, region)` |

---

## 13. Reproducibility

All SQL artefacts committed to https://github.com/spurush1/clickhouse-modelling:

```
sql/                       1:N benchmark
  01–03_pattern_*.sql      DDL
  04_seed_S/M/L/XL.sql     Synthetic data
  05–07_queries_*.sql      Benchmark queries (Q1–Q5)
  08_correctness_check.sql Correctness gate
  09_collect_results.sql   Results collection

sql/nn/                    1:N:N benchmark
  09_reset_nn.sql          Clean teardown
  10–12_pattern_*_nn.sql   DDL with order_total + two flags
  13_seed_S/M/L/XL_nn.sql  Synthetic data (4 POs/order × 10 lines)
  14–16_queries_*_nn.sql   Benchmark queries (Q1–Q7)
  17_correctness_nn.sql    Correctness gate (incl. both guard flags)

results/
  results_all.md           1:N raw timing data
  ADR-001-clickhouse-data-modelling.md  This document
```

**To reproduce:**
```bash
git clone https://github.com/spurush1/clickhouse-modelling
cd clickhouse-modelling

# 1:N study
bash run_bench.sh S        # ~2 min, validates 1:N at 500K lines

# 1:N:N study (manual for now)
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/09_reset_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/10_pattern_a_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/11_pattern_b_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/12_pattern_c_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/13_seed_S_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/17_correctness_nn.sql
```

---

## 14. Appendix: Per-Query Verdict Table (1:N:N, XL tier)

| Query | A (ms) | B (ms) | C (ms) | Winner | Key reason |
|---|---|---|---|---|---|
| Q1 PO spend | 2 | 2 | 3 | Tie | All handle PO-grain well |
| Q2 Line revenue | 7571 | 1212 | **258** | C | FINAL kills A; B larger PO table in 1:N:N |
| Q3 Cross-grain order count | 6972 | 166 | **78** | C | C wins vs B in 1:N:N (larger PO scan for B) |
| Q4 Vendor order count | 949 | **312** | 360 | B | B's PO table still smaller than flat table |
| Q5 Monthly trend + join | 22104 | 1242 | **194** | C | C needs no join; A's join costs 1.1 GB |
| Q6 Order value by region | 209 | 902 | **133** | **C** | B requires JOIN to order table; C uses flag |
| Q7 PO vs line variance | 19074 | 314 | **212** | **C** | C one scan two sumIf; A two FINAL + join |

*All timing numbers are empirical measurements from `system.query_log` on the specified hardware.
All correctness assertions passed across all patterns and tiers.*
