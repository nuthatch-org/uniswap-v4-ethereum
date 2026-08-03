-- Swap-decode invariants over the same pinned window.
--
-- The important one is `opposite_sign_swaps`: V4 swap amounts are signed from the pool's
-- perspective, so amount0 and amount1 must have opposite signs on every ordinary swap. If a
-- decoder ever mangled the int128 sign bit, this number would diverge immediately.
--
-- The three buckets are disjoint and MUST sum to `swaps`:
--
--   opposite_sign_swaps + zero_leg_swaps + dec_overflow_swaps = swaps
--
-- That third bucket is not padding. `int128` reaches 39 digits, but the `_dec` companion is
-- DECIMAL(38,0), so genuinely large amounts overflow it to NULL — and a NULL compares as neither
-- zero nor opposite-signed, so it vanishes from both other buckets. The sampled window contains
-- exactly 3 such swaps, all on pool 0x6aac69b7…, with amounts of 39 and 40 digits.
--
-- Counting them explicitly turns a silent gap into an asserted number: if the reconciliation ever
-- breaks, either the decode changed or the overflow behaviour did. Raw text columns are always
-- exact — only the `_dec` companions overflow.
SELECT
    count(*)                                                            AS swaps,
    count(DISTINCT id)                                                  AS pools_traded,
    count(DISTINCT sender)                                              AS distinct_senders,
    count(*) FILTER (WHERE amount0_dec IS NULL OR amount1_dec IS NULL)  AS dec_overflow_swaps,
    count(*) FILTER (
        WHERE amount0_dec IS NOT NULL AND amount1_dec IS NOT NULL
          AND (amount0_dec = 0 OR amount1_dec = 0)
    )                                                                   AS zero_leg_swaps,
    count(*) FILTER (
        WHERE amount0_dec <> 0 AND amount1_dec <> 0
          AND sign(amount0_dec) <> sign(amount1_dec)
    )                                                                   AS opposite_sign_swaps
FROM "pool_manager__swap"
WHERE block_number BETWEEN 25653052 AND 25672988;
