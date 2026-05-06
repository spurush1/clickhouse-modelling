#!/usr/bin/env bash
# run_bench.sh — End-to-end ClickHouse modelling benchmark
# Works in WSL, Git Bash, or any bash-compatible shell on Windows.
#
# Usage:
#   bash run_bench.sh [TIER]       # run a single tier: S, M, L, XL
#   bash run_bench.sh              # run all four tiers
#
# Prerequisites:
#   - Docker Desktop running
#   - No port conflicts on 8123 / 9000

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/sql"
RESULTS_DIR="$SCRIPT_DIR/results"
SCORPIO_COMPOSE="${SCORPIO_COMPOSE:-}"   # optional: path to scorpio docker-compose.yml

CH_CONTAINER="ch-bench"
CH_IMAGE="clickhouse/clickhouse-server:24.3-alpine"
CH_HOST="localhost"
CH_PORT="8123"
CH_USER="default"
CH_PASS=""

TIERS=("S" "M" "L" "XL")
if [[ $# -ge 1 ]]; then
    TIERS=("$1")
fi

mkdir -p "$RESULTS_DIR"

# ── Helpers ──────────────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

ch_query() {
    # Execute a SQL string against the bench container via HTTP
    local sql="$1"
    curl -s --fail \
        -X POST "http://${CH_HOST}:${CH_PORT}/" \
        --user "${CH_USER}:${CH_PASS}" \
        --data-binary "$sql"
}

ch_file() {
    # Execute a SQL file — replace TIER placeholder first
    local file="$1"
    local tier="${2:-}"
    local sql
    sql="$(cat "$file")"
    if [[ -n "$tier" ]]; then
        sql="${sql//TIER/$tier}"
    fi
    curl -s --fail \
        -X POST "http://${CH_HOST}:${CH_PORT}/" \
        --user "${CH_USER}:${CH_PASS}" \
        --data-binary "$sql"
}

wait_for_ch() {
    log "Waiting for ClickHouse to be ready..."
    local retries=30
    until ch_query "SELECT 1" > /dev/null 2>&1 || [[ $retries -eq 0 ]]; do
        sleep 2
        ((retries--))
    done
    if [[ $retries -eq 0 ]]; then
        log "ERROR: ClickHouse did not start in time"; exit 1
    fi
    log "ClickHouse is ready."
}

# ── Environment setup ────────────────────────────────────────────────────────

log "=== ClickHouse Modelling Benchmark ==="
log "Tiers to run: ${TIERS[*]}"

# Stop Scorpio stack if path provided
if [[ -n "$SCORPIO_COMPOSE" && -f "$SCORPIO_COMPOSE" ]]; then
    log "Stopping Scorpio stack..."
    docker compose -f "$SCORPIO_COMPOSE" stop
fi

# Remove any leftover bench container
docker rm -f "$CH_CONTAINER" 2>/dev/null || true

log "Starting isolated ClickHouse container ($CH_IMAGE)..."
docker run -d \
    --name "$CH_CONTAINER" \
    --cpus="12" \
    --memory="24g" \
    -p "${CH_PORT}:8123" \
    -p "9900:9000" \
    "$CH_IMAGE"

wait_for_ch

# ── Run tiers ────────────────────────────────────────────────────────────────

for TIER in "${TIERS[@]}"; do
    log ""
    log "════════════════════════════════════════"
    log "  TIER: $TIER"
    log "════════════════════════════════════════"

    log "Setting up database..."
    ch_file "$SQL_DIR/00_setup_db.sql"

    log "Creating Pattern A schema..."
    ch_file "$SQL_DIR/01_pattern_a.sql"

    log "Creating Pattern B schema..."
    ch_file "$SQL_DIR/02_pattern_b.sql"

    log "Creating Pattern C schema..."
    ch_file "$SQL_DIR/03_pattern_c.sql"

    log "Seeding data (tier $TIER) — this may take a while for L/XL..."
    ch_file "$SQL_DIR/04_seed_${TIER}.sql"
    log "Seeding complete."

    # Run each query file 5 times with the TIER tag substituted
    for PATTERN_FILE in \
        "$SQL_DIR/05_queries_a.sql" \
        "$SQL_DIR/06_queries_b.sql" \
        "$SQL_DIR/07_queries_c.sql"; do
        PATTERN_LABEL=$(basename "$PATTERN_FILE" .sql | cut -d_ -f3 | tr '[:lower:]' '[:upper:]')
        log "Running Pattern $PATTERN_LABEL queries (5 runs)..."
        for RUN in 1 2 3 4 5; do
            ch_file "$PATTERN_FILE" "$TIER" > /dev/null
        done
    done

    log "Running correctness check..."
    CORRECTNESS=$(ch_file "$SQL_DIR/08_correctness_check.sql" "$TIER")
    echo "$CORRECTNESS"
    if echo "$CORRECTNESS" | grep -q "FAIL"; then
        log "ERROR: Correctness check FAILED for tier $TIER — aborting."
        exit 1
    fi
    log "Correctness: all checks PASSED."

    log "Collecting results..."
    RESULTS=$(ch_file "$SQL_DIR/09_collect_results.sql" "$TIER")
    RESULT_FILE="$RESULTS_DIR/results_${TIER}.md"

    {
        echo "# Benchmark Results — Tier $TIER"
        echo ""
        echo "Generated: $(date)"
        echo ""
        echo "| query_id | pattern | tier | runs | median_ms | min_ms | max_ms | peak_mem_mb | rows_read |"
        echo "|---|---|---|---|---|---|---|---|---|"
        echo "$RESULTS" | while IFS=$'\t' read -r qid pat tier runs med mi ma mem rr _; do
            echo "| $qid | $pat | $tier | $runs | $med | $mi | $ma | $mem | $rr |"
        done
    } > "$RESULT_FILE"

    log "Results written to $RESULT_FILE"
done

# ── Summary ──────────────────────────────────────────────────────────────────

log ""
log "════════════════════════════════════════"
log "  SUMMARY (median_ms, all tiers)"
log "════════════════════════════════════════"
ch_query "
SELECT
    query_id, pattern, tier, median_ms
FROM (
    SELECT
        extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][1]  AS query_id,
        extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][2]  AS pattern,
        extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][3]  AS tier,
        medianIf(query_duration_ms, run_number > 1)  AS median_ms
    FROM (
        SELECT query, query_duration_ms,
               row_number() OVER (
                   PARTITION BY
                       extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][1],
                       extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][2],
                       extractAllGroups(query, 'bench:(Q\\\\d+):(\\\\w+):(\\\\w+)')[1][3]
                   ORDER BY event_time
               ) AS run_number
        FROM system.query_log
        WHERE query LIKE '%bench:Q%' AND type = 'QueryFinish'
          AND query NOT LIKE '%system.query_log%'
    )
    GROUP BY query_id, pattern, tier
)
ORDER BY query_id, tier, pattern
FORMAT PrettyCompact
"

# ── Cleanup ──────────────────────────────────────────────────────────────────

log ""
log "Removing bench container..."
docker rm -f "$CH_CONTAINER"

if [[ -n "$SCORPIO_COMPOSE" && -f "$SCORPIO_COMPOSE" ]]; then
    log "Restarting Scorpio stack..."
    docker compose -f "$SCORPIO_COMPOSE" up -d
fi

log "Done. Result files in: $RESULTS_DIR"
