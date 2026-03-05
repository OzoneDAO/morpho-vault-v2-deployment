# sUSDS/USDT Market Migration

Migrate the [USDT Savings vault](https://app.morpho.org/ethereum/vault/0x23f5E9c35820f4baB695Ac1F19c203cC3f8e1e11/skymoney-usdt-savings) from the existing sUSDS/USDT market (DAI/USD oracle, uncapped USDT) to a new market using USDS/USD oracle and USDT/USD capped at $1.00.

Curator/allocator: `0x3F32bC09d41eE699844F8296e806417D6bf61Bba`

## Step 0: Deploy Oracle & Market (Script)

Run from any EOA. Deploys CappedOracleFeed (USDT/USD capped at $1), Morpho oracle, creates and seeds the new sUSDS/USDT market (96.5% LLTV, 90% utilization).

Prerequisites: 2 USDT + 2.1 sUSDS.

```bash
source .env
forge script script/usdt_savings_market_migration/DeployOracleAndMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
```

Export from console output:
```bash
export VAULT_ADDRESS=0x23f5E9c35820f4baB695Ac1F19c203cC3f8e1e11
export CAPPED_USDT_FEED=0x...
export NEW_ORACLE=0x...
```

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/1_*" --fork-url $RPC_URL -v
```

## Step 1: Submit Cap Increases (3-day timelock)

**Curator app** > USDT Savings vault > Markets > Add Market

Msig submits two timelocked calls on the vault:
- `submit(increaseAbsoluteCap(newMarketCapId, type(uint128).max))`
- `submit(increaseRelativeCap(newMarketCapId, 1e18))`

This starts a **3-day timelock**. Caps are not yet active.

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/2_*" --fork-url $RPC_URL -v
```

## Step 2: Execute Cap Increases (Day 3+)

**Curator app** > USDT Savings vault > Pending Actions > Execute

Msig executes the two pending calls (after timelock has elapsed):
- `increaseAbsoluteCap(newMarketCapId, type(uint128).max)`
- `increaseRelativeCap(newMarketCapId, 1e18)`

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/3_*" --fork-url $RPC_URL -v
```

## Step 3: Switch Liquidity Adapter

**Curator app** > USDT Savings vault > Settings > Liquidity Adapter

Msig calls (no timelock):
- `setLiquidityAdapterAndData(adapter, abi.encode(newMarketParams))`

From this point, **all new deposits go to the new market**.

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/4_*" --fork-url $RPC_URL -v
```

## Step 4: Reallocate Capital (Old -> New)

**Curator app** > USDT Savings vault > Allocate

Msig calls (repeat as liquidity frees up):
- `deallocate(adapter, abi.encode(oldMarketParams), amount)` — withdraw available idle from old market
- `allocate(adapter, abi.encode(newMarketParams), amount)` — deposit idle USDT to new market

Max withdrawable per round = `min(vault.allocation(oldCapId), morphoMarket.totalSupply - morphoMarket.totalBorrow)`. Rising rates on the old market incentivize borrowers to repay, freeing more liquidity over time.

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/5_*" --fork-url $RPC_URL -v
```

## Step 5: Cleanup — Zero Old Market Caps

**Curator app** > USDT Savings vault > Markets > old sUSDS/USDT market

Msig calls (no timelock for decreases):
- `decreaseAbsoluteCap(oldMarketCapId, 0)`
- `decreaseRelativeCap(oldMarketCapId, 0)`

Verify:
```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/6_*" --fork-url $RPC_URL -v
```

## Run All Migration Tests

```bash
forge test --match-path "test/usdt_savings_market_migration/deployed/*" --fork-url $RPC_URL -v
```

## Timeline

| Day | Action |
|-----|--------|
| 0 | Step 0: Deploy oracle + market. Step 1: Submit caps (starts 3-day timelock) |
| 3+ | Step 2: Execute caps. Step 3: Switch liquidity adapter |
| 3+ | Step 4: Reallocate (may take multiple rounds over days/weeks) |
| End | Step 5: Zero out old market caps |
