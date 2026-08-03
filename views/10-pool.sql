-- Pool entity. In V4 there is no pool *contract* — every pool lives inside the singleton
-- PoolManager and is identified by a `bytes32` PoolId. `Initialize` is the only place a pool's
-- immutable key (currencies, fee, tick spacing, hooks) is ever emitted, so this view is the
-- lookup table everything else joins against.
--
-- `currency0 = 0x0000…0000` means native ETH, not a missing value — V4 supports ETH directly
-- rather than requiring WETH.
CREATE VIEW pool AS
SELECT
    id                          AS id,
    currency0                   AS currency0,
    currency1                   AS currency1,
    fee                         AS fee,
    -- 0x800000 (8388608) is V4's DYNAMIC_FEE_FLAG, not a fee of 838.8608%. A pool carrying it
    -- has its fee set per-swap by its hook, so the static `fee` column is meaningless there —
    -- read `fee` off pool_manager__swap instead, which records what was actually charged.
    -- 55 of the 1,019 pools in the sampled window carry this flag; sorting pools by `fee`
    -- without accounting for it puts them all at the top.
    fee = 8388608               AS fee_is_dynamic,
    tickSpacing                 AS tick_spacing,
    hooks                       AS hooks,
    hooks <> '0x0000000000000000000000000000000000000000' AS has_hook,
    sqrtPriceX96                AS initial_sqrt_price_x96,
    tick                        AS initial_tick,
    block_number                AS created_block,
    block_timestamp             AS created_at,
    tx_hash                     AS created_tx
FROM "pool_manager__initialize";
