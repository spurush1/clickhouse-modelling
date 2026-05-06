# ClickHouse Data Modelling Benchmark

Empirical benchmark comparing three ClickHouse data modelling patterns for
procurement hierarchies, validated across four data-volume tiers (500K → 100M rows).
Motivated by a real NLP2SQL workload where an LLM generates SQL on the fly — the data
model must make correct queries easy and incorrect queries obviously wrong.

Two structural problems are studied:

- **Study 1 — 1:N** — `order → po_line` (one parent, many children; single header grain)
- **Study 2 — 1:N:N** — `order → purchase_order → po_line` (two parent levels, two header grains)

Full architecture decision record: [`results/ADR-001-clickhouse-data-modelling.md`](results/ADR-001-clickhouse-data-modelling.md)

---

## The Core Problem

Flattening a parent-child hierarchy into a single table repeats parent-level fields on
every child row. Naive `SUM(parent_metric)` overcounts by the number of children:

```sql
-- 1:N: PO with 10 lines → po_total counted 10×
SELECT vendor_id, SUM(po_total) FROM flat_table GROUP BY vendor_id;  -- WRONG

-- 1:N:N: order with 4 POs × 10 lines → order_total counted 40×
SELECT region, SUM(order_total) FROM flat_table GROUP BY region;     -- WRONG
```

ClickHouse's historically weak JOIN support makes normalised alternatives expensive.
This benchmark measures whether guard-flag denormalization, nested arrays, or co-sorted
joins is the best tradeoff — and which is safest for an LLM writing SQL dynamically.

---

## Three Patterns

| Pattern | Design | Double-count mechanism |
|---|---|---|
| **A** | Co-sorted `ReplacingMergeTree` tables + HASHED dictionary | Separate table per grain; `FINAL` for dedup; `full_sorting_merge` join |
| **B** | Nested `Array()` columns — one row per PO, lines packed inside | Scalar header columns never double-count; `ARRAY JOIN` for line access |
| **C** | Flat denormalized line-grain table + boolean guard flags | `is_first_line_of_po=1` guards PO metrics; `is_first_line_of_order=1` guards order metrics |

---

## Hardware and Setup

| Item | Detail |
|---|---|
| CPU | Intel i7-12700H — 14 cores / 20 threads |
| RAM | 32 GB (Docker Desktop limited to 4 CPUs / 16 GB) |
| Storage | NVMe SSD, 294 GB free |
| ClickHouse | 24.3.18-alpine, isolated container, no other services running |
| Measurement | 5 runs per query; median reported; sourced from `system.query_log` |

---

## Data Volumes

### Study 1 — 1:N (order → po_line, effective 1:40 ratio)

| Tier | po_line rows | POs | Orders |
|---|---|---|---|
| S | 500,000 | 50,000 | 12,500 |
| M | 1,000,000 | 100,000 | 25,000 |
| L | 10,000,000 | 1,000,000 | 250,000 |
| XL | 100,000,000 | 10,000,000 | 2,500,000 |

### Study 2 — 1:N:N (order → PO → po_line, 4 POs per order × 10 lines per PO)

Same po_line row counts as Study 1, now with a true two-level hierarchy and a distinct
`order_total` metric at the order grain.

---

## Benchmark Queries

### Study 1 — Q1–Q5

| # | Business question | Grain |
|---|---|---|
| Q1 | Total PO spend by vendor (last 30 days) | PO header |
| Q2 | Revenue by product_id | Line |
| Q3 | Count orders containing product_id = 42 | Cross-grain |
| Q4 | Top 10 vendors by order count | Cross-grain (PO→order) |
| Q5 | Monthly line revenue trend by vendor + region | Line + time + join |

### Study 2 — Q1–Q7 (adds two order-grain queries)

| # | Business question | Grain | What it tests |
|---|---|---|---|
| Q1–Q5 | Same as Study 1 | — | Baseline comparison |
| Q6 | Total **order** value by region | **Order header** | Second guard flag `is_first_line_of_order` |
| Q7 | PO committed spend vs actual line spend variance | **Both grains** | Both flags in one query |

---

## Results Summary

### Study 1 — 1:N at XL (100M lines, median ms)

| Query | Pattern A | Pattern B | Pattern C | Winner |
|---|---|---|---|---|
| Q1 PO spend | 3 | 2 | 2 | Tie |
| Q2 Line revenue | **7,415** | 524 | **268** | C (27.7× faster than A) |
| Q3 Cross-grain | **6,810** | **76** | 87 | B ≈ C |
| Q4 Vendor count | 1,228 | **135** | 296 | B |
| Q5 Join + trend | **21,892** | 563 | **182** | C (120× faster than A) |

### Study 2 — 1:N:N at XL (100M lines, median ms)

| Query | Pattern A | Pattern B | Pattern C | Winner |
|---|---|---|---|---|
| Q1 PO spend | 2 | 2 | 3 | Tie |
| Q2 Line revenue | **7,571** | 1,212 | **258** | C |
| Q3 Cross-grain | **6,972** | 166 | **78** | C (B degrades 2× vs Study 1) |
| Q4 Vendor count | 949 | **312** | 360 | B |
| Q5 Join + trend | **22,104** | 1,242 | **194** | C |
| **Q6 Order value** | 209 | **902** | **133** | **C** (B needs JOIN to order table) |
| **Q7 PO vs line variance** | **19,074** | 314 | **212** | **C** |

### Peak memory at XL — key comparisons

| Query | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| Q2 Line revenue | 730 MB | 61–64 MB | **9–10 MB** |
| Q5 Join + trend | 1,091–1,126 MB | 66–68 MB | **14–15 MB** |
| Q6 Order value | 90 MB | **831 MB** | **6 MB** |
| Q7 PO vs line variance | 951 MB | 18 MB | **10 MB** |

---

## Key Findings

### 1. Pattern A (co-sorted + FINAL) is unusable at scale

`FINAL` on `ReplacingMergeTree` forces a full deduplication scan at query time —
it cannot be skipped even when there are no duplicates. At 100M lines, every analytical
query costs 7–22 seconds. The `full_sorting_merge` join optimization helps but cannot
overcome the scan cost. **Pattern A is disqualified for any table above ~5M rows in a
query-latency-sensitive workload.**

### 2. Pattern B breaks at the order grain in 1:N:N

Pattern B was competitive in Study 1 for PO-grain and cross-grain queries. But in
Study 2 — when the question involves the *order* grain — Pattern B must `JOIN` to a
separate `order_b` table. At XL, Q6 costs **902ms and 831MB RAM** for Pattern B vs
**133ms and 6MB** for Pattern C. The nested-array model has no mechanism to absorb a
second parent grain without an additional join.

### 3. Pattern C's two-flag approach solves 1:N:N cleanly and cheaply

The second guard flag `is_first_line_of_order` adds:
- **1 byte per row** (UInt8, compresses to ~1 bit in practice)
- **1 prompt rule** for the NLP2SQL agent (`sumIf(order_total, is_first_line_of_order=1)`)
- **Zero query overhead** — identical execution to any other `sumIf` on a UInt8 column

The general rule: for N levels of hierarchy above the line, add N guard flags. Cost is
O(1) per additional level. All 24 correctness checks (6 assertions × 4 tiers) PASSED.

### 4. Pattern B has an ETL memory wall at XL

At XL tier (100M lines / 10M POs), building Pattern B via `groupArray()` in a single
INSERT exceeds 14GB RAM and OOM-crashes. Pattern C at XL also requires batched inserts
for the 3-table JOIN + double window function. Pattern A inserts independently per
table with no aggregation — it has the simplest write pipeline.

### 5. NLP2SQL verdict: Pattern C wins by a wide margin

| LLM requirement | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| Standard SQL only | ❌ FINAL, dictGet | ❌ ARRAY JOIN | ✅ |
| Single table for all questions | ❌ 3 tables | ❌ 2 tables | ✅ |
| No join knowledge needed | ❌ always joins | ⚠️ sometimes | ✅ |
| Failure mode is obvious | ❌ silently wrong | ❌ syntax error | ✅ 10× overcount |
| Prompt rules needed | 4 rules | 3 rules | **2 rules** |

---

## Recommendation

**Use Pattern C (flat denormalized + guard flags) for all procurement gold marts.**

For 1:N:N, the canonical DDL is:

```sql
CREATE TABLE gold_procurement_mart (
    po_date       Date,
    vendor_id     UInt32,
    po_id         UInt64,
    line_id       UInt32,
    order_id      UInt64,
    order_total   Decimal(18,2),   -- sumIf(order_total, is_first_line_of_order=1)
    region        LowCardinality(String),
    po_total      Decimal(18,2),   -- sumIf(po_total, is_first_line_of_po=1)
    product_id    UInt32,
    quantity      UInt32,
    line_amount   Decimal(18,2),   -- SUM directly
    is_first_line_of_po     UInt8,
    is_first_line_of_order  UInt8
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(po_date)
  ORDER BY (po_date, vendor_id, order_id, po_id, line_id);
```

NLP2SQL system prompt (3 rules):

```
- line_amount, quantity  → SUM directly
- po_total    → sumIf(po_total,    is_first_line_of_po    = 1)
- order_total → sumIf(order_total, is_first_line_of_order = 1)
No JOIN, FINAL, ARRAY JOIN, or dictGet needed.
```

---

## Inspiration and References

The three patterns did not emerge in a vacuum. Each is grounded in published production
engineering from companies running ClickHouse at scale. Below is the lineage of ideas
that shaped each pattern and the modelling approach taken in this benchmark.

---

### Pattern A — Co-sorted tables + full_sorting_merge

**Core idea**: Keep data normalized; make JOINs cheap by physically co-sorting related
tables on the join key so the merge-sort phase is skipped at query time.

**Primary references:**

| Source | What it contributed |
|---|---|
| [ClickHouse blog — Joins Under the Hood Part 3: Full Sorting Merge](https://clickhouse.com/blog/clickhouse-fully-supports-joins-full-sort-partial-merge-part3) | Detailed mechanics of how `full_sorting_merge` skips the sort phase when `ORDER BY` matches the join key. The foundational paper for why co-sorting works. |
| [ClickHouse blog — Choosing the Right Join Algorithm Part 5](https://clickhouse.com/blog/clickhouse-fully-supports-joins-how-to-choose-the-right-algorithm-part5) | Benchmark comparison of all ClickHouse join algorithms with memory/time tradeoffs. Shows `full_sorting_merge` is competitive with hash join at a fraction of the memory when tables are co-sorted. |
| [ClickHouse official docs — Using JOINs](https://clickhouse.com/docs/guides/joining-tables) | Decision tree for choosing join strategy; confirms the co-sort pattern. |
| [Tinybird engineering blog — ClickHouse data modelling patterns](https://www.tinybird.co/blog-posts/working-with-clickhouse-joins) | Documented the "fact + header co-sorted" pattern as a production best practice; advocated for same leading ORDER BY column across related tables. |
| [PostHog open-source codebase](https://github.com/PostHog/posthog) | PostHog uses separate `ReplacingMergeTree` tables per entity grain (events, sessions, persons), all co-sorted on the relationship key. Pattern A's structure is directly inspired by this approach. |

**Why we tested it**: The promise of `full_sorting_merge` — join speed with O(block)
memory — was compelling. The benchmark revealed the fatal flaw: `FINAL` on
`ReplacingMergeTree` imposes a full deduplication scan at query time that
`full_sorting_merge` cannot compensate for at scale.

---

### Pattern B — Nested arrays / ARRAY JOIN

**Core idea**: Store the parent entity once with children packed into parallel `Array()`
columns. ClickHouse's columnar storage means array elements of the same type are stored
contiguously — line items for all POs are physically co-located.

**Primary references:**

| Source | What it contributed |
|---|---|
| [ClickHouse official docs — Array data type and ARRAY JOIN](https://clickhouse.com/docs/en/sql-reference/statements/select/array-join) | Native documentation for the ARRAY JOIN clause, array functions (`has`, `arrayFilter`, `arraySum`), and the Nested type. This is the canonical reference for how arrays are stored and queried. |
| [ClickHouse blog — Using Arrays in ClickHouse](https://clickhouse.com/blog/aggregate-functions-combinators-in-clickhouse-for-arrays) | Explains `groupArray` / `groupArrayState` for building arrays from rows, and how `arraySum`, `arrayMap`, `arrayFilter` replace traditional aggregations on exploded data. |
| [Cloudflare Engineering — HTTP Analytics for 6M requests/second](https://blog.cloudflare.com/http-analytics-for-6m-requests-per-second-using-clickhouse/) | Cloudflare stores DNS event sub-records as nested arrays inside parent events to avoid cross-table joins in their highest-QPS query paths. Inspired the "pack children into the parent row" approach. |
| [ClickHouse docs — Nested data structures](https://clickhouse.com/docs/en/sql-reference/data-types/nested-data-structures/nested) | Clarified that `Nested` is syntactic sugar for parallel `Array()` columns — each array must have the same length, and they are stored as separate columns internally. |
| [Altinity knowledge base — Nested arrays patterns](https://kb.altinity.com/altinity-kb-schema-design/nested/) | Published guidance on when Nested/Array is appropriate (append-only, bounded child counts, no BI tools) vs when to avoid it. Directly informed the "avoid when lines update independently" rule. |

**Why we tested it**: Array storage is genuinely ClickHouse-idiomatic for sub-entity
data. The benchmark confirmed it is fast for header aggregations and `has()` membership
tests, but revealed the memory wall at scale (`groupArray` OOM at 10M POs) and the
cross-grain join cost when a second parent level is introduced (Q6 in Study 2).

---

### Pattern C — Flat denormalized + guard flags

**Core idea**: Pre-join everything at ingest time. Use deterministic boolean markers to
identify exactly one representative row per parent entity, making `sumIf(metric, flag=1)`
produce correct header-grain aggregations from a line-grain table.

**Primary references:**

| Source | What it contributed |
|---|---|
| [eBay Engineering — OLAP Journey with ClickHouse on Kubernetes](https://innovation.ebayinc.com/stories/ou-online-analytical-processing/) | eBay processes ~1 billion OLAP events per minute using fully denormalized flat tables with LowCardinality columns. Their core insight: push complexity to the ETL pipeline, keep query-time logic simple. This is the philosophical foundation of Pattern C. |
| [Uber Engineering — M3 and large-scale analytics](https://www.uber.com/en-IN/blog/logging/) | Uber's ClickHouse deployment for trip analytics uses flat wide tables at the event grain with all parent attributes repeated. Header-level metrics are handled at the semantic/query layer, not the storage layer. |
| [ClickHouse blog — Denormalization strategies](https://clickhouse.com/blog/denormalizing-data-in-clickhouse-for-better-query-performance) | Official ClickHouse guidance explicitly recommends denormalization for analytical workloads: "ClickHouse is optimized for reading large amounts of data from wide, flat tables." |
| [The Data Warehouse Toolkit — Kimball, Ross (3rd ed.)](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/books/data-warehouse-dw-toolkit/) | Kimball's "fact table at the lowest grain" principle is the direct intellectual ancestor of Pattern C. The `is_first_line` guard flag is a ClickHouse-specific implementation of Kimball's "degenerate dimension" concept applied to avoid double-counting in columnar stores. |
| [dbt docs — Grain and fan-out in data modelling](https://docs.getdbt.com/terms/grain) | The fan-out problem (joining a table to a finer-grain table multiplies rows and overcounts aggregates) is well-documented in the modern data stack community. Pattern C solves fan-out at the storage layer rather than the query layer. |
| [ClickHouse docs — sumIf and countIf combinators](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/combinators#-if) | The `-If` aggregate combinator — `sumIf(expr, cond)` — is the ClickHouse primitive that makes the guard-flag pattern efficient. It evaluates the condition per row with no intermediate materialisation. |

**The guard-flag generalisation** (N flags for N parent grains) is an original
contribution of this benchmark. The idea of using a `min()` window function to
deterministically select one representative row per group is a standard SQL technique;
applying it as a pre-computed stored column for two independent parent grains in a
ClickHouse flat table — and proving its correctness and near-zero overhead empirically
— is the novel finding of the 1:N:N study.

---

### NLP2SQL context

The NLP2SQL constraint — that the data model must be safe for LLM-generated SQL — drew
from the following:

| Source | What it contributed |
|---|---|
| [Text-to-SQL survey — Dail-SQL, BIRD benchmark](https://bird-bench.github.io/) | Research showing LLM SQL generation accuracy drops significantly with JOIN complexity and schema size. Motivated the "fewest tables, standard SQL" design goal. |
| [Anthropic prompting guide — structured outputs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags) | Claude-specific guidance on providing structured schema context in prompts. Informed the token-efficient system prompt design for Pattern C (3 rules vs 4 for Pattern A). |
| [ClickHouse community — NLP2SQL and LLM integration](https://clickhouse.com/blog/building-a-real-time-analytics-with-clickhouse-and-gpt-4) | ClickHouse's own experiments integrating GPT-4 with ClickHouse schemas. Confirmed that LLMs struggle with ClickHouse-specific syntax (`FINAL`, `ARRAY JOIN`, `dictGet`) when not given explicit rules. |

---

## File Layout

```
sql/                         Study 1 — 1:N benchmark
  00_setup_db.sql            Drop + create bench database
  01_pattern_a.sql           Pattern A DDL (3 co-sorted tables + dictionary)
  02_pattern_b.sql           Pattern B DDL (nested arrays)
  03_pattern_c.sql           Pattern C DDL (flat line-grain + is_first_line)
  04_seed_S/M/L/XL.sql      Synthetic data generation per tier
  05_queries_a.sql           Q1–Q5 for Pattern A
  06_queries_b.sql           Q1–Q5 for Pattern B
  07_queries_c.sql           Q1–Q5 for Pattern C
  08_correctness_check.sql   Cross-pattern result comparison (PASS/FAIL)
  09_collect_results.sql     Pull timings from system.query_log

sql/nn/                      Study 2 — 1:N:N benchmark
  09_reset_nn.sql            Drop all 1:N:N objects (dict first, then tables)
  10_pattern_a_nn.sql        Pattern A DDL with order_total + order_dict_nn
  11_pattern_b_nn.sql        Pattern B DDL with order_b_nn table
  12_pattern_c_nn.sql        Pattern C DDL with two guard flags
  13_seed_S/M/L/XL_nn.sql   Synthetic data (4 POs/order × 10 lines/PO)
  14_queries_a_nn.sql        Q1–Q7 for Pattern A
  15_queries_b_nn.sql        Q1–Q7 for Pattern B
  16_queries_c_nn.sql        Q1–Q7 for Pattern C
  17_correctness_nn.sql      Correctness gate (validates both guard flags)

results/
  results_all.md             Raw 1:N timing data
  ADR-001-clickhouse-data-modelling.md  Full architecture decision record

run_bench.sh                 Orchestrator for Study 1 (Study 2 is manual)
```

## Running the Benchmark

### Prerequisites

- Docker Desktop running
- WSL, Git Bash, or any bash shell
- No port conflicts on 8123 / 9000

### Study 1 — 1:N (automated)

```bash
bash run_bench.sh S      # ~2 min — tier S only, good for validation
bash run_bench.sh        # ~45 min — all four tiers
```

### Study 2 — 1:N:N (manual per tier)

```bash
# Start an isolated ClickHouse container first
docker run -d --name ch-bench --cpus="4" --memory="16g" \
  -p 8123:8123 clickhouse/clickhouse-server:24.3-alpine
until docker exec ch-bench clickhouse-client --query "SELECT 1" 2>/dev/null; do sleep 2; done

# Run tier S (replace S with M / L / XL for other tiers)
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/09_reset_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/10_pattern_a_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/11_pattern_b_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/12_pattern_c_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/13_seed_S_nn.sql
docker exec -i ch-bench clickhouse-client --multiquery < sql/nn/17_correctness_nn.sql
```

### Collect results after running

```bash
docker exec -i ch-bench clickhouse-client --multiquery < sql/09_collect_results.sql
```
