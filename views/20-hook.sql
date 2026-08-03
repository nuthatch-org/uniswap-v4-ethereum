-- Hook adoption — the view that has no V3 equivalent.
--
-- Hooks are V4's headline feature: a pool may delegate to a contract that runs before/after
-- swaps and liquidity changes. The hook address is part of the pool key, so it is fixed at
-- Initialize and can never change for that pool.
--
-- V4 encodes a hook's PERMISSIONS in the low bits of its own address — which callbacks it may
-- receive is literally a property of where it was deployed (hence the vanity-mined addresses).
-- This view exposes the raw address and lets you decode flags yourself; it deliberately does not
-- guess at the bit layout, which is a protocol constant this nest has no business hard-coding.
CREATE VIEW hook AS
SELECT
    p.hooks                             AS hook_address,
    count(*)                            AS pools,
    count(DISTINCT p.currency0)         AS distinct_currency0,
    count(DISTINCT p.currency1)         AS distinct_currency1,
    min(p.created_block)                AS first_pool_block,
    max(p.created_block)                AS last_pool_block
FROM pool p
WHERE p.has_hook
GROUP BY p.hooks;

-- The headline split: how much of V4 actually uses hooks at all.
CREATE VIEW hook_adoption AS
SELECT
    has_hook                                        AS uses_hook,
    count(*)                                        AS pools,
    round(100.0 * count(*) / (SELECT count(*) FROM pool), 2) AS pct_of_pools
FROM pool
GROUP BY has_hook;
