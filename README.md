# Uniswap V4 nest — Ethereum mainnet

A [nuthatch](https://github.com/nuthatch-org/nuthatch) indexer for **Uniswap V4** on Ethereum
mainnet: the singleton PoolManager at `0x000000000004444c5dc75cB358380D2e3dE08A90`.

One Rust binary reads the chain over plain JSON-RPC and gives you a local SQL database plus an HTTP
API. No Postgres, no Docker, no subgraph, no hosted service, no API key.

```sh
cargo install --git https://github.com/nuthatch-org/nuthatch nuthatch
cd uniswap-v4
export RPC=https://your-mainnet-archive-node/     # keep the URL in your environment, not the repo

# 1. Index recent history (~2 min for 20k blocks), Ctrl-C at "sealing history done"
nuthatch dev --seal-direct --backfill 20000 --concurrency 8 --rpc "$RPC"

# 2. Start again — serves the API, loads the views, follows the tip
nuthatch dev --rpc "$RPC"

nuthatch sql --url http://127.0.0.1:8288 "SELECT uses_hook, pools, pct_of_pools FROM hook_adoption"
```

> **Why two steps?** Views load once at startup. On a cold nest there is no data yet, so every view
> fails with `Catalog Error: Table … does not exist` and you get raw tables only. Restarting after
> the backfill loads them. You pay this once.

---

## Read this before you backfill

**V4 mainnet is big.** Measured, not estimated:

| | |
|---|---|
| PoolManager deployed | block 21,688,329 |
| Blocks to current tip | ~3,984,694 |
| Event density | **17.1 events/block** |
| Full history | **~68M events** |
| Throughput measured | **2,785 events/sec** (8-way, Alchemy) |
| **Full backfill** | **~7 hours** |

The `--backfill 20000` in the quickstart is deliberate: it gives you a working, queryable index of
recent history in about two minutes. Full history is a genuine several-hour job and wants your own
archive node, not a public endpoint.

This is the opposite trade from a nest like [`poa-nest`](https://github.com/nuthatch-org/poa-nest),
where the whole of history is 951 events and syncs in a minute. Here the *config* is trivial and the
*volume* is the work.

Pick your depth:

```sh
nuthatch dev --seal-direct --backfill 20000   --concurrency 8 --rpc "$RPC"   # ~2 min, recent
nuthatch dev --seal-direct --backfill 500000  --concurrency 8 --rpc "$RPC"   # ~50 min
nuthatch dev --seal-direct                    --concurrency 8 --rpc "$RPC"   # ~7 h, from deployment
```

### RPC endpoints

Measured 2026-08-03 for archive depth and JSON-RPC batch size >3 (the block-timestamp fetcher
batches, and a batch cap stalls indexing in a way that looks like slowness):

| Endpoint | Archive | Batch >3 | Verdict |
|---|---|---|---|
| `eth.api.onfinality.io/public` | ✅ | ✅ | shipped default |
| `ethereum-rpc.publicnode.com` | ✅ | ✅ | shipped default |
| `rpc.flashbots.net` | ✅ | ✅ | shipped default |
| `1rpc.io/eth` | ✅ | ✅ | shipped default |
| `eth-pokt.nodies.app` | ✅ | ✅ | shipped default; 403s under sustained load |
| `eth.drpc.org` | ✅ | ❌ capped at 3 | **unusable** — timestamps never complete |
| `rpc.ankr.com/eth`, `eth.llamarpc.com` | ❌ | ❌ | no usable response |

The defaults work for a small `--backfill`. For real history use your own node via `--rpc`, which is
tried first and keeps the defaults as fallback — so your URL never has to enter this repo.

---

## What makes V4 different (and why this nest is simple)

**There is no factory and there are no pool contracts.** In V3, every pool is a deployed contract
discovered from `PoolCreated` — that's why the V3 nest needs nuthatch's factory machinery. In V4,
every pool lives *inside* the singleton and is identified by a `bytes32` PoolId.

So this nest is **one static contract, no `[[templates]]`, no `[[factories]]`**. The entire protocol
is 10 event tables.

---

## The data model

### Views

| View | What it is |
|---|---|
| `pool` | Pool key: currencies, fee, tick spacing, hooks, plus `has_hook` and `fee_is_dynamic` |
| `hook` | Per-hook adoption — how many pools each hook backs |
| `hook_adoption` | The headline split: what share of pools use a hook at all |
| `pool_activity` | Per-pool swaps, distinct senders, absolute volume |
| `pool_liquidity` | Per-pool liquidity added, removed, net, distinct providers |

```sh
nuthatch sql "SELECT uses_hook, pools, pct_of_pools FROM hook_adoption"
nuthatch sql "SELECT hook_address, pools FROM hook ORDER BY pools DESC LIMIT 10"
nuthatch sql "SELECT pool_id, swaps, has_hook FROM pool_activity ORDER BY swaps DESC LIMIT 10"
```

From the sampled window (19,936 blocks, ~2.8 days of mainnet): 1,019 pools created, **32% of them
using a hook**, 311k swaps.

### Raw tables

`pool_manager__` + the event name: `swap`, `initialize`, `modify_liquidity`, `donate`, `transfer`,
`approval`, `operator_set`, `protocol_fee_updated`, `protocol_fee_controller_updated`,
`ownership_transferred`. Every row also carries `block_number`, `block_timestamp`, `block_hash`,
`tx_hash`, `log_index` and `address`. `curl localhost:8288/schema` describes all of them.

### Five things that will bite you

1. **Swap amounts are signed from the pool's perspective.** Negative = the pool paid out. The two
   amounts always have opposite signs, so summing raw amounts nets to ~zero, not to volume. Use
   `abs()` — `pool_activity` already does.

2. **`fee = 8388608` is not an 838% fee.** `0x800000` is V4's `DYNAMIC_FEE_FLAG`: that pool's fee is
   set per-swap by its hook. 55 of the 1,019 sampled pools carry it, and sorting by `fee` without
   accounting for it puts them all at the top. Use `pool.fee_is_dynamic`, and read the *actual* fee
   charged from `pool_manager__swap.fee`.

3. **`currency0 = 0x0000…0000` means native ETH**, not a missing value. V4 supports ETH directly
   rather than requiring WETH — 384 of the sampled pools are native-ETH pools.

4. **Big-int `_dec` companions can overflow to NULL.** `int128` reaches 39 digits; the `_dec`
   companion is `DECIMAL(38,0)`. The sampled window has exactly **3** swaps whose amounts (39 and 40
   digits) overflow it. A NULL is neither zero nor opposite-signed, so such rows silently vanish from
   naive filters — `checks/parity_swaps.sql` counts them explicitly so the three buckets reconcile
   exactly to the swap total. The raw text columns are always exact; only `_dec` overflows.

5. **`pool_manager__transfer` is not pool tokens.** It is the ERC-6909 claim-token ledger — balances
   held inside the PoolManager instead of settling to ERC-20 on every operation.

### Not included

No USD pricing and no token symbols/decimals. Both need a token list or an oracle, and the
declarative core makes no contract calls. `sqrtPriceX96` is the raw pool price; converting it to a
human ratio needs both tokens' decimals — a client-side join.

---

## Verify it

```sh
nuthatch check --dir .      # stop `nuthatch dev` first — check reads the store directly
```

Two checks, both bounded to the pinned window `25653052..25672988` so they stay deterministic as the
chain advances. `parity_swaps` asserts the sign invariant *and* the bucket reconciliation from
gotcha 4. Re-record with `--update` after an intentional change.

---

## Layout

```
nuthatch.toml     one contract — the whole config
abis/             PoolManager ABI, resolved from Sourcify by `nuthatch init`
views/            5 entity views as plain CREATE VIEW SQL
checks/           2 invariant checks + recorded fixtures
semantic.toml     what each table means (agents read this via the schema tool)
schema.json       DERIVED from nuthatch.toml — drives the `_dec` columns
llms.txt          DERIVED — the AI-facing surface
segments/         sealed Parquet history — regenerable
nuthatch.redb     hot store near the tip — regenerable
```

If you hand-edit `nuthatch.toml`, run `nuthatch schema` afterwards — `schema.json` is what generates
the `_dec` columns, and without it they silently disappear while `/schema` still advertises them.
