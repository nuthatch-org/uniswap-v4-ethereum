-- Pool-key invariants over a pinned block range.
--
-- Bounded by block_number so the fixtures stay deterministic as the chain advances. The range is
-- the sampled window this nest was first validated against; if you backfill deeper the counts
-- below are unaffected, because they are windowed rather than totals.
--
-- What this actually asserts:
--   * every pool has a distinct PoolId (it is a keccak of the key, so collisions would be a
--     decode bug, not a protocol event)
--   * the dynamic-fee flag is decoded as itself and not silently coerced
--   * native-ETH pools exist, which is the V4 behaviour a V3-shaped decoder would get wrong
SELECT
    count(*)                                                    AS pools,
    count(DISTINCT id)                                          AS distinct_pool_ids,
    count(*) FILTER (WHERE hooks <> '0x0000000000000000000000000000000000000000') AS pools_with_hook,
    count(*) FILTER (WHERE fee = 8388608)                       AS dynamic_fee_pools,
    count(*) FILTER (WHERE currency0 = '0x0000000000000000000000000000000000000000') AS native_eth_pools
FROM "pool_manager__initialize"
WHERE block_number BETWEEN 25653052 AND 25672988;
