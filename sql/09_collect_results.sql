-- 09_collect_results.sql
-- Pull benchmark timings from system.query_log.
-- Run after all query files have completed for the current tier.

SELECT
    extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][1]  AS query_id,
    extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][2]  AS pattern,
    extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][3]  AS tier,
    count()                                                         AS runs,
    -- Exclude run 1 (warm-up) from timing; take median of remaining runs
    medianIf(query_duration_ms, run_number > 1)                     AS median_ms,
    minIf(query_duration_ms, run_number > 1)                        AS min_ms,
    maxIf(query_duration_ms, run_number > 1)                        AS max_ms,
    round(max(memory_usage) / 1e6, 1)                              AS peak_mem_mb,
    any(read_rows)                                                  AS rows_read,
    any(read_bytes)                                                 AS bytes_read
FROM (
    SELECT
        query,
        query_duration_ms,
        memory_usage,
        read_rows,
        read_bytes,
        -- Assign run number per (query_id, pattern, tier) group by arrival order
        row_number() OVER (
            PARTITION BY
                extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][1],
                extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][2],
                extractAllGroups(query, 'bench:(Q\\d+):(\\w+):(\\w+)')[1][3]
            ORDER BY event_time
        ) AS run_number
    FROM system.query_log
    WHERE query LIKE '%bench:Q%'
      AND type = 'QueryFinish'
      AND event_time >= now() - INTERVAL 3 HOUR
      AND query NOT LIKE '%system.query_log%'
)
GROUP BY query_id, pattern, tier
ORDER BY query_id, tier, pattern;
