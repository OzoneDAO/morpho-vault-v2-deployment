# Morpho Vault V2 Deployment

Foundry scripts, tests, and allocator bot for deploying **Morpho Vault V2** vaults on Ethereum mainnet.

## Overview

This repository deploys single-market and multi-market stUSDS-collateralized Morpho vaults:

| Vault | Loan Token | Strategy | Collateral | LLTV |
|-------|-----------|----------|------------|------|
| **USDS Risk Capital** | USDS | Single-market, auto-allocation | stUSDS | 86% |
| **USDC Risk Capital** | USDC | Single-market, auto-allocation | stUSDS | 86% |
| **USDT Risk Capital** | USDT | Single-market, auto-allocation | stUSDS | 86% |
| **USDT Savings** | USDT | Single-market, auto-allocation | sUSDS | 96.5% |
| **Flagship** | USDS | Multi-market, manual allocation | stUSDS, cbBTC, wstETH, WETH | 86% |

## Repository Structure

```
.
├── script/
│   ├── usds_risk_capital/
│   │   └── DeployUsdsRiskCapital.s.sol
│   ├── usdc_risk_capital/
│   │   └── DeployUsdcRiskCapital.s.sol
│   ├── usdt_risk_capital/
│   │   └── DeployUsdtRiskCapital.s.sol
│   ├── usdt_savings/
│   │   └── DeployUsdtSavings.s.sol
│   ├── usdt_savings_market_migration/
│   │   ├── DeployOracleAndMarket.s.sol
│   │   └── README.md
│   └── flagship/
│       ├── 1_CreateVault.s.sol
│       ├── 2_CreateCbBtcMarket.s.sol
│       ├── 3_CreateWstEthMarket.s.sol
│       ├── 4_CreateWethMarket.s.sol
│       └── 5_ConfigureVault.s.sol
├── src/lib/
│   ├── Constants.sol
│   └── DeployHelpers.sol
├── test/
│   ├── base/
│   │   ├── BaseVaultTest.sol
│   │   └── BaseDeployedVaultTest.sol
│   ├── usds_risk_capital/
│   │   ├── DeployUsdsRiskCapitalScript.t.sol
│   │   └── DeployedUsdsRiskCapitalVault.t.sol
│   ├── usdc_risk_capital/
│   │   ├── DeployUsdcRiskCapitalScript.t.sol
│   │   └── DeployedUsdcRiskCapitalVault.t.sol
│   ├── usdt_risk_capital/
│   │   ├── DeployUsdtRiskCapitalScript.t.sol
│   │   └── DeployedUsdtRiskCapitalVault.t.sol
│   ├── usdt_savings/
│   │   ├── DeployUsdtSavingsScript.t.sol
│   │   └── DeployedUsdtSavingsVault.t.sol
│   ├── usdt_savings_market_migration/
│   │   ├── DeployMigrationScript.t.sol
│   │   └── deployed/
│   │       ├── BaseMigrationTest.sol
│   │       ├── 1_DeployOracleAndMarket.t.sol
│   │       ├── 2_SubmitCaps.t.sol
│   │       ├── 3_ExecuteCaps.t.sol
│   │       ├── 4_SwitchLiquidityAdapter.t.sol
│   │       ├── 5_Reallocate.t.sol
│   │       └── 6_Cleanup.t.sol
│   └── flagship/
│       ├── DeployFlagshipScript.t.sol
│       └── deployed/
│           ├── 1_CreateVault.t.sol
│           ├── 2_CreateCbBtcMarket.t.sol
│           ├── 3_CreateWstEthMarket.t.sol
│           ├── 4_CreateWethMarket.t.sol
│           └── 5_ConfigureVault.t.sol
└── bot/
    ├── src/allocator.ts
    └── README.md
```

## Vaults

### Single-Market Vaults (Auto-Allocation)

All four single-market vaults share the same architecture:
- **Liquidity Adapter**: Deposits auto-allocate to the Morpho Blue market
- **Collateral**: stUSDS (ERC4626)
- **Deployment**: Single script each

| Vault | Loan Token | LLTV | Oracle |
|-------|-----------|------|--------|
| **USDS Risk Capital** | USDS (18 dec) | 86% | stUSDS ERC4626 redemption rate only |
| **USDC Risk Capital** | USDC (6 dec) | 86% | stUSDS ERC4626 + USDS/USD & USDC/USD Chainlink |
| **USDT Risk Capital** | USDT (6 dec) | 86% | stUSDS ERC4626 + USDS/USD & USDT/USD Chainlink |
| **USDT Savings** | USDT (6 dec) | 96.5% | sUSDS ERC4626 + USDS/USD & CappedUSDT/USD (migrated from DAI/USD & uncapped USDT/USD) |

### Flagship Vault (Multi-Market)

- **Strategy**: 80% idle (earns SSR via Merkl), 20% allocated to markets
- **Allocation**: Manual via allocator bot (no liquidity adapter)
- **Markets** (all 86% LLTV):
  - stUSDS/USDS (existing market)
  - cbBTC/USDS
  - wstETH/USDS
  - WETH/USDS
- **Caps**: 20% max to adapter, 5% max per market
- **Deployment**: 5 sequential scripts

### USDT Savings Market Migration

The USDT Savings vault was initially deployed using an existing sUSDS/USDT market with DAI/USD oracle and uncapped USDT/USD feed. A migration moves it to a new market with USDS/USD oracle and USDT/USD capped at $1.00 (to prevent liquidations from USDT being overpriced).

- **Script**: `script/usdt_savings_market_migration/DeployOracleAndMarket.s.sol` — deploys capped oracle, Morpho oracle, creates and seeds new market
- **Migration steps** (via [Morpho Curator app](https://curator.morpho.org/vaults)): submit caps (3-day timelock), execute caps, switch liquidity adapter, reallocate, cleanup
- **Guide**: [`script/usdt_savings_market_migration/README.md`](script/usdt_savings_market_migration/README.md)

## Installation

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
forge install
```

## Testing

### Script Tests (pre-deployment)

Run deployment scripts in-memory on an Anvil fork to verify they produce correct output:

```bash
source .env
anvil --fork-url $RPC_URL &
sleep 5

# Run all script tests
forge test --match-path "test/*/Deploy*Script.t.sol" --fork-url http://localhost:8545 -v
forge test --match-path "test/flagship/DeployFlagshipScript*" --fork-url http://localhost:8545 -v

# Migration script test
forge test --match-path "test/usdt_savings_market_migration/DeployMigrationScript*" --fork-url http://localhost:8545 -v

# Or run individually
forge test --match-contract DeployUsdsRiskCapitalScript --fork-url http://localhost:8545 -v
forge test --match-contract DeployUsdcRiskCapitalScript --fork-url http://localhost:8545 -v
forge test --match-contract DeployUsdtRiskCapitalScript --fork-url http://localhost:8545 -v
forge test --match-contract DeployUsdtSavingsScript --fork-url http://localhost:8545 -v
forge test --match-contract DeployFlagshipScript --fork-url http://localhost:8545 -v

pkill anvil
```

### Deployed Tests (post-deployment)

After each mainnet deployment, run the corresponding test to verify on-chain state. These run directly against the RPC (no Anvil needed):

```bash
source .env  # Must contain VAULT_ADDRESS and other deployment outputs

# Single-market vaults
forge test --match-contract DeployedUsdsRiskCapitalVault --fork-url $RPC_URL --fork-block-number $USDS_BLOCK_NUMBER -v
forge test --match-contract DeployedUsdcRiskCapitalVault --fork-url $RPC_URL --fork-block-number $USDC_BLOCK_NUMBER -v
forge test --match-contract DeployedUsdtRiskCapitalVault --fork-url $RPC_URL --fork-block-number $USDT_RC_BLOCK_NUMBER -v
forge test --match-contract DeployedUsdtSavingsVault --fork-url $RPC_URL --fork-block-number $USDT_SAV_BLOCK_NUMBER -v

# Flagship (incremental after each script)
forge test --match-path "test/flagship/deployed/1_*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v
forge test --match-path "test/flagship/deployed/2_*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v
forge test --match-path "test/flagship/deployed/3_*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v
forge test --match-path "test/flagship/deployed/4_*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v
forge test --match-path "test/flagship/deployed/5_*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v

# Or all Flagship deployed tests at once
forge test --match-path "test/flagship/deployed/*" --fork-url $RPC_URL --fork-block-number $FLAGSHIP_BLOCK_NUMBER -v

# Migration deployed tests (incremental, one per step)
# Requires: VAULT_ADDRESS, NEW_ORACLE, CAPPED_USDT_FEED
forge test --match-path "test/usdt_savings_market_migration/deployed/1_*" --fork-url $RPC_URL -v
forge test --match-path "test/usdt_savings_market_migration/deployed/2_*" --fork-url $RPC_URL -v
forge test --match-path "test/usdt_savings_market_migration/deployed/3_*" --fork-url $RPC_URL -v
forge test --match-path "test/usdt_savings_market_migration/deployed/4_*" --fork-url $RPC_URL -v
forge test --match-path "test/usdt_savings_market_migration/deployed/5_*" --fork-url $RPC_URL -v
forge test --match-path "test/usdt_savings_market_migration/deployed/6_*" --fork-url $RPC_URL -v
```

## Deployment

### Environment Variables

Create a `.env` file:

```bash
# Required
PRIVATE_KEY=0x...
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Optional (defaults to deployer address)
OWNER=0x...           # Final owner (multisig recommended)
CURATOR=0x...         # Manages vault config via timelock
ALLOCATOR=0x...       # Safe 1/3 multisig address for Flagship vault
SENTINEL=0x...        # Can revoke timelocked actions

# Optional (custom naming)
VAULT_NAME="Custom Vault Name"
VAULT_SYMBOL="customVaultSymbol"
```

### Deploy Single-Market Vaults

Each vault is a single script:

```bash
source .env

# USDS Risk Capital
forge script script/usds_risk_capital/DeployUsdsRiskCapital.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

# USDC Risk Capital
forge script script/usdc_risk_capital/DeployUsdcRiskCapital.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

# USDT Risk Capital
forge script script/usdt_risk_capital/DeployUsdtRiskCapital.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

# USDT Savings
forge script script/usdt_savings/DeployUsdtSavings.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
```

### Deploy Flagship Vault (5 Scripts)

```bash
source .env

# Step 1: Create Vault and Adapter
forge script script/flagship/1_CreateVault.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
# Set env vars from output: VAULT_ADDRESS, ADAPTER_ADDRESS

# Step 2: Create cbBTC/USDS Market
forge script script/flagship/2_CreateCbBtcMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
# Set: ORACLE_CBBTC

# Step 3: Create wstETH/USDS Market
forge script script/flagship/3_CreateWstEthMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
# Set: ORACLE_WSTETH

# Step 4: Create WETH/USDS Market
forge script script/flagship/4_CreateWethMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
# Set: ORACLE_WETH

# Step 5: Configure Vault (caps, timelocks, ownership)
forge script script/flagship/5_ConfigureVault.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
```

## Allocator Bot

The Flagship vault requires an allocator bot to maintain the 80% idle / 20% allocated strategy. The bot executes transactions through a **Safe 1/3 multisig** (threshold 1, 3 owners). The Safe address is set as the vault's allocator, and the bot autonomously signs and executes via `execTransaction`.

```bash
cd bot
npm install
cp .env.example .env
# Fill in SAFE_ADDRESS, PRIVATE_KEY (bot signer), and deployment addresses

DRY_RUN=true npm run dev  # Test with dry run
npm run dev                # Run for real
```

See [bot/README.md](bot/README.md) and [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) for details.

## Role Hierarchy

| Role | Set By | Permissions |
|------|--------|-------------|
| **Owner** | Current Owner | Set curator, sentinels, transfer ownership |
| **Curator** | Owner | Timelocked: adapters, caps, allocators |
| **Allocator** | Curator | Allocate/deallocate capital, set liquidity adapter |
| **Sentinel** | Owner | Revoke pending timelocked actions |

## Timelock Requirements

Per Morpho listing rules:

| Duration | Actions |
|----------|---------|
| **7 days** | `increaseTimelock`, `removeAdapter`, `abdicate` |
| **3 days** | `addAdapter`, `increaseAbsoluteCap`, `increaseRelativeCap`, `setForceDeallocatePenalty`, `burnShares`, `setSkimRecipient` |

## Key Addresses (Mainnet)

```
# Tokens
USDS:    0xdC035D45d973E3EC169d2276DDab16f1e407384F
USDC:    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
USDT:    0xdAC17F958D2ee523a2206206994597C13D831ec7
stUSDS:  0x99CD4Ec3f88A45940936F469E4bB72A2A701EEB9
sUSDS:   0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD
WETH:    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
wstETH:  0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
cbBTC:   0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf

# Chainlink Feeds
DAI/USD:   0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9
USDS/USD:  0xfF30586cD0F29eD462364C7e81375FC0C71219b1
USDC/USD:  0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
USDT/USD:  0x3E7d1eAB13ad0104d2750B8863b489D65364e32D
CBBTC/USD: 0x2665701293fCbEB223D11A08D826563EDcCE423A
STETH/USD: 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8
ETH/USD:   0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419

# Morpho Infrastructure
MORPHO_BLUE:      0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
IRM_ADAPTIVE:     0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC
ADAPTER_REGISTRY: 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e
```

## Deployment Costs

| Vault | Gas (~ETH) | Tokens Needed |
|-------|------------|---------------|
| USDS Risk Capital | ~0.0015 | 2 USDS, 2.1 stUSDS |
| USDC Risk Capital | ~0.0015 | 2 USDC, 2.1 stUSDS |
| USDT Risk Capital | ~0.0015 | 2 USDT, 2.1 stUSDS |
| USDT Savings | ~0.0005 | 1 USDT (reuses existing market) |
| Flagship | ~0.003 | ~4 USDS, 0.001 wstETH, 0.001 WETH, 0.0001 cbBTC |

## Troubleshooting

### "Out of gas" on Tenderly
USDS has complex transfer logic. Use `--gas-estimate-multiplier 200`.

### USDT approve reverts
USDT's `approve()` doesn't return a bool (non-standard ERC20). All USDT scripts use `SafeERC20.forceApprove()`.

### Test Failures
- Script tests require Anvil running; deployed tests run directly against RPC
- Run tests sequentially with `-j 1` if env var race conditions occur
- Create fresh fork for clean state

### Market Already Exists
Scripts handle this gracefully with try/catch. Safe to re-run.

### Stale Fork IRM Overflow (USDT Savings)
When reusing an existing market with borrows on a stale Tenderly fork, the adaptive IRM overflows computing `exp(speed * elapsed)` for large `elapsed`. The deployment script avoids this by doing the dead deposit before setting the liquidity adapter (so the deposit stays idle). Deployed tests use `vm.warp(market.lastUpdate + 1)` before deposits.
