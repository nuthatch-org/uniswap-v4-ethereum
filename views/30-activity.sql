-- Per-pool trading activity, joined back to the pool key.
--
-- On amounts: V4 `Swap` amounts are `int128` and SIGNED FROM THE POOL'S PERSPECTIVE — negative
-- means the pool paid out, positive means it took in. So a swap's two amounts always have
-- opposite signs, and summing raw amounts nets to roughly zero rather than to volume. Volume
-- therefore uses abs(). The `_dec` companions are exact DECIMAL(38,0) and safe here: int128
-- maxes out at 39 digits but real token amounts are nowhere near it.
--
-- Deliberately absent: USD pricing. That needs a token list and an oracle, neither of which this
-- nest has — the declarative core makes no contract calls. `sqrt_price_x96` is the raw pool price
-- and converting it to a human ratio needs both tokens' decimals, which is a client-side join.
CREATE VIEW pool_activity AS
SELECT
    p.id                                AS pool_id,
    p.currency0                         AS currency0,
    p.currency1                         AS currency1,
    p.fee                               AS fee,
    p.hooks                             AS hooks,
    p.has_hook                          AS has_hook,
    count(s.id)                         AS swaps,
    count(DISTINCT s.sender)            AS distinct_senders,
    sum(abs(s.amount0_dec))             AS volume0_abs,
    sum(abs(s.amount1_dec))             AS volume1_abs,
    min(s.block_number)                 AS first_swap_block,
    max(s.block_number)                 AS last_swap_block
FROM pool p
LEFT JOIN "pool_manager__swap" s ON s.id = p.id
GROUP BY p.id, p.currency0, p.currency1, p.fee, p.hooks, p.has_hook;

-- Liquidity provision per pool. `liquidityDelta` is signed: positive adds, negative removes.
CREATE VIEW pool_liquidity AS
SELECT
    id                                                          AS pool_id,
    count(*)                                                    AS modify_events,
    count(DISTINCT sender)                                      AS distinct_providers,
    sum(liquidityDelta_dec)                                     AS net_liquidity_delta,
    sum(liquidityDelta_dec) FILTER (WHERE liquidityDelta_dec > 0) AS added,
    sum(liquidityDelta_dec) FILTER (WHERE liquidityDelta_dec < 0) AS removed,
    min(block_number)                                           AS first_block,
    max(block_number)                                           AS last_block
FROM "pool_manager__modify_liquidity"
GROUP BY id;
