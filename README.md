# ClickHouse Data Modelling Benchmark

Benchmark comparing three ClickHouse design patterns for a classic one-to-many
`order → purchase_order → po_line` hierarchy.

## The Problem

Naive denormalization of a parent-child relationship into a single flat table causes
**double-counting** of header-level metrics (e.g. `po_total`) when aggregating.
ClickHouse's traditional weakness with JOINs makes this a real engineering tradeoff.

## Three Patterns Tested

| Pattern | Design | Double-count handled by |
|---|---|---|
| **A** | Co-sorted `ReplacingMergeTree` tables + HASHED dictionary | Naturally — separate tables per grain |
| **B** | Nested arrays (`Array` columns, one row per PO) | Naturally — scalar columns for header, arrays for lines |
| **C** | Flat denormalized line-grain table | `is_first_line = 1` marker + `sumIf` / `countIf` |

## Hardware

Benchmarked on: Intel i7-12700H (14 cores / 20 threads), 32 GB RAM, NVMe SSD.
ClickHouse version: 24.3-alpine.

## Data Volumes (4 tiers)

| Tier | po_line rows | PO rows | Order rows |
|---|---|---|---|
| S | 500 000 | 50 000 | 12 500 |
| M | 1 000 000 | 100 000 | 25 000 |
| L | 10 000 000 | 1 000 000 | 250 000 |
| XL | 100 000 000 | 10 000 000 | 2 500 000 |

## Benchmark Queries (Q1–Q5)

| # | Question | Grain |
|---|---|---|
| Q1 | Total spend by vendor (last 30 days) | Header |
| Q2 | Revenue by product_id | Line |
| Q3 | Count orders containing product_id = 42 | Cross-grain |
| Q4 | Top 10 vendors by order count | Header |
| Q5 | Monthly line-amount trend by vendor | Line + time |

Each query runs 5 times; run 1 is warm-up. Median of runs 2–5 is reported.

## File Layout

```
sql/
  00_setup_db.sql          — Drop + create bench database
  01_pattern_a.sql         — Pattern A DDL (3 tables + dictionary)
  02_pattern_b.sql         — Pattern B DDL (nested arrays)
  03_pattern_c.sql         — Pattern C DDL (flat line-grain)
  04_seed_S/M/L/XL.sql    — Synthetic data generation per tier
  05_queries_a.sql         — Q1-Q5 for Pattern A
  06_queries_b.sql         — Q1-Q5 for Pattern B
  07_queries_c.sql         — Q1-Q5 for Pattern C
  08_correctness_check.sql — Cross-pattern result comparison (PASS/FAIL)
  09_collect_results.sql   — Pull timings from system.query_log

results/
  results_S.md / results_M.md / results_L.md / results_XL.md

run_bench.sh               — Full orchestrator (stops services, runs, collects)
```

## Running the Benchmark

### Prerequisites

- Docker Desktop running on Windows
- WSL, Git Bash, or any bash shell
- No port conflicts on 8123 / 9000

### Quick start (single tier)

```bash
# Run tier S only (fast, ~2 minutes)
bash run_bench.sh S

# Run tier M
bash run_bench.sh M
```

### Full run (all four tiers)

```bash
bash run_bench.sh
```

### With Scorpio stack (stops other services for pristine environment)

```bash
SCORPIO_COMPOSE=/path/to/scorpio/infra/docker-compose.yml bash run_bench.sh
```

### Manual step-by-step (for debugging)

```bash
# Start isolated container
docker run -d --name ch-bench --cpus="12" --memory="24g" \
  -p 8123:8123 -p 9900:9000 clickhouse/clickhouse-server:24.3-alpine

# Wait for readiness
until docker exec ch-bench clickhouse-client --query "SELECT 1"; do sleep 2; done

# Run individual SQL files
curl -s -X POST http://localhost:8123/ --data-binary @sql/00_setup_db.sql
curl -s -X POST http://localhost:8123/ --data-binary @sql/01_pattern_a.sql
# ... etc

# Tear down
docker rm -f ch-bench
```

## Reading Results

`results/results_<TIER>.md` contains:

| Column | Meaning |
|---|---|
| `median_ms` | Median query time (ms) across runs 2–5 |
| `min_ms / max_ms` | Variance across runs |
| `peak_mem_mb` | Peak memory used by the query |
| `rows_read` | Rows scanned (lower = better index use) |

Lower `median_ms` and `rows_read` are better.
Pattern C Q1/Q4 results without `is_first_line` filtering = double-counting bug demonstration.

## Key Findings (to be filled after running)

> Results will be populated here after benchmark runs complete.

## References

- [ClickHouse Joins Under the Hood — Part 3 (full_sorting_merge)](https://clickhouse.com/blog/clickhouse-fully-supports-joins-full-sort-partial-merge-part3)
- [Choosing the Right Join Algorithm — Part 5 (benchmarks)](https://clickhouse.com/blog/clickhouse-fully-supports-joins-how-to-choose-the-right-algorithm-part5)
- [eBay OLAP Journey with ClickHouse](https://innovation.ebayinc.com/stories/ou-online-analytical-processing/)
- [Cloudflare HTTP Analytics for 6M req/sec](https://blog.cloudflare.com/http-analytics-for-6m-requests-per-second-using-clickhouse/)
