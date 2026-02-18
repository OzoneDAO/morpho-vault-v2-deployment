# Morpho Vault V2 Deployment

Foundry scripts, tests, and allocator bot for deploying **Morpho Vault V2** vaults on Ethereum mainnet.

## Overview

This repository deploys single-market and multi-market USDS-based Morpho vaults:

| Vault | Loan Token | Strategy | Collateral | LLTV |
|-------|-----------|----------|------------|------|
| **USDS Risk Capital** | USDS | Single-market, auto-allocation | stUSDS | 86% |
| **USDC Risk Capital** | USDC | Single-market, auto-allocation | stUSDS | 86% |
| **USDT Risk Capital** | USDT | Single-market, auto-allocation | stUSDS | 86% |
| **USDT Savings** | USDT | Single-market, auto-allocation | stUSDS | 96.5% |
| **Flagship** | USDS | Multi-market, manual allocation | stUSDS, cbBTC, wstETH, WETH | 86% |

## Repository Structure

```
.
├── script/
│   ├── usds_risk_capital/
│   │   └── DeployUsdsRiskCapital.s.sol      # USDS Risk Capital vault (1 script)
│   ├── usdc_risk_capital/
│   │   └── DeployUsdcRiskCapital.s.sol      # USDC Risk Capital vault (1 script)
│   ├── usdt_risk_capital/
│   │   └── DeployUsdtRiskCapital.s.sol      # USDT Risk Capital vault (1 script)
│   ├── usdt_savings/
│   │   └── DeployUsdtSavings.s.sol          # USDT Savings vault (1 script)
│   └── flagship/
│       ├── 1_CreateVault.s.sol              # Deploy vault + adapter
│       ├── 2_CreateCbBtcMarket.s.sol        # Create cbBTC/USDS market
│       ├── 3_CreateWstEthMarket.s.sol       # Create wstETH/USDS market
│       ├── 4_CreateWethMarket.s.sol         # Create WETH/USDS market
│       └── 5_ConfigureVault.s.sol           # Configure caps, timelocks, ownership
├── src/lib/
│   ├── Constants.sol                         # Mainnet addresses & parameters
│   └── DeployHelpers.sol                     # Shared deployment utilities
├── test/
│   ├── usds_risk_capital/
│   │   ├── DeployUsdsRiskCapitalScript.t.sol    # Script tests
│   │   └── DeployedUsdsRiskCapitalVault.t.sol   # Deployed tests
│   ├── usdc_risk_capital/
│   │   ├── DeployUsdcRiskCapitalScript.t.sol    # Script tests
│   │   └── DeployedUsdcRiskCapitalVault.t.sol   # Deployed tests
│   ├── usdt_risk_capital/
│   │   ├── DeployUsdtRiskCapitalScript.t.sol    # Script tests
│   │   └── DeployedUsdtRiskCapitalVault.t.sol   # Deployed tests
│   ├── usdt_savings/
│   │   ├── DeployUsdtSavingsScript.t.sol        # Script tests
│   │   └── DeployedUsdtSavingsVault.t.sol       # Deployed tests
│   ├── flagship/
│   │   ├── DeployFlagshipScript.t.sol           # Script tests
│   │   └── deployed/                            # Deployed tests (1 per script)
│   │       ├── 1_CreateVault.t.sol
│   │       ├── 2_CreateCbBtcMarket.t.sol
│   │       ├── 3_CreateWstEthMarket.t.sol
│   │       ├── 4_CreateWethMarket.t.sol
│   │       └── 5_ConfigureVault.t.sol
│   └── base/
│       ├── BaseVaultTest.sol                    # Shared script test suite
│       └── BaseDeployedVaultTest.sol            # Shared deployed test suite
├── bot/
│   ├── src/allocator.ts                      # Allocator bot (executes via Safe multisig)
│   └── README.md                             # Bot documentation
└── DEPLOYMENT_SEQUENCE.md                    # Full deployment order (scripts + Safe + bot)
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
| **USDT Savings** | USDT (6 dec) | 96.5% | stUSDS ERC4626 + USDS/USD & USDT/USD Chainlink |

### Flagship Vault (Multi-Market)

- **Purpose**: Higher yield through diversified lending across multiple collateral types
- **Strategy**: 80% idle (earns SSR via Merkl), 20% allocated to markets
- **No Liquidity Adapter**: Deposits stay idle; allocator bot manages allocation
- **Markets** (all 86% LLTV):
  - stUSDS/USDS (existing market from USDS Risk Capital vault)
  - cbBTC/USDS (new market)
  - wstETH/USDS (new market)
  - WETH/USDS (new market)
- **Caps**: 20% max to adapter, 5% max per market
- **Deployment**: 5 sequential scripts

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

# Or run individually
forge test --match-path "test/usds_risk_capital/*Script*" --fork-url http://localhost:8545 -v
forge test --match-path "test/usdc_risk_capital/*Script*" --fork-url http://localhost:8545 -v
forge test --match-path "test/usdt_risk_capital/*Script*" --fork-url http://localhost:8545 -v
forge test --match-path "test/usdt_savings/*Script*" --fork-url http://localhost:8545 -v
forge test --match-path "test/flagship/DeployFlagshipScript*" --fork-url http://localhost:8545 -v

pkill anvil
```

### Deployed Tests (post-deployment, incremental)

After each mainnet deployment script, run the corresponding test to verify on-chain state:

```bash
source .env  # Must contain VAULT_ADDRESS and other deployment outputs

# Single-market vaults (after deployment)
forge test --match-contract DeployedUsdsRiskCapitalVault --fork-url $RPC_URL -v
forge test --match-contract DeployedUsdcRiskCapitalVault --fork-url $RPC_URL -v
forge test --match-contract DeployedUsdtRiskCapitalVault --fork-url $RPC_URL -v
forge test --match-contract DeployedUsdtSavingsVault --fork-url $RPC_URL -v

# Flagship (incremental after each script)
forge test --match-path "test/flagship/deployed/1_*" --fork-url $RPC_URL -v   # after script 1
forge test --match-path "test/flagship/deployed/2_*" --fork-url $RPC_URL -v   # after script 2
forge test --match-path "test/flagship/deployed/3_*" --fork-url $RPC_URL -v   # after script 3
forge test --match-path "test/flagship/deployed/4_*" --fork-url $RPC_URL -v   # after script 4
forge test --match-path "test/flagship/deployed/5_*" --fork-url $RPC_URL -v   # after script 5

# Or run all Flagship deployed tests at once
forge test --match-path "test/flagship/deployed/*" --fork-url $RPC_URL -v
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

The Flagship vault deployment is split into 5 sequential scripts for better control and verification:

```bash
source .env

# Step 1: Create Vault and Adapter
forge script script/flagship/1_CreateVault.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

# Set env vars from output
export VAULT_ADDRESS=0x...
export ADAPTER_ADDRESS=0x...

# Step 2: Create cbBTC/USDS Market
forge script script/flagship/2_CreateCbBtcMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

export ORACLE_CBBTC=0x...

# Step 3: Create wstETH/USDS Market
forge script script/flagship/3_CreateWstEthMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

export ORACLE_WSTETH=0x...

# Step 4: Create WETH/USDS Market
forge script script/flagship/4_CreateWethMarket.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200

export ORACLE_WETH=0x...

# Step 5: Configure Vault (caps, timelocks, ownership)
forge script script/flagship/5_ConfigureVault.s.sol \
  --rpc-url $RPC_URL --broadcast --slow --gas-estimate-multiplier 200
```

**Note**: The Flagship vault reuses the existing stUSDS/USDS market from the USDS Risk Capital vault deployment.

## Allocator Bot

The Flagship vault requires an allocator bot to maintain the 80% idle / 20% allocated strategy. The bot executes transactions through a **Safe 1/3 multisig** (threshold 1, 3 owners). The Safe address is set as the vault's allocator, and the bot autonomously signs and executes via `execTransaction`.

### Setup

1. Create a Safe multisig at [app.safe.global](https://app.safe.global) with threshold=1 and 3 owners (one being the bot's EOA)
2. Use the Safe address as `ALLOCATOR` during vault deployment (Script 5)
3. Configure the bot:

```bash
cd bot
npm install
cp .env.example .env
# Fill in SAFE_ADDRESS, PRIVATE_KEY (bot signer), and deployment addresses

# Test with dry run
DRY_RUN=true npm run dev

# Run for real
npm run dev
```

See [bot/README.md](bot/README.md) and [DEPLOYMENT_SEQUENCE.md](DEPLOYMENT_SEQUENCE.md) for details.

## Role Hierarchy

| Role | Set By | Permissions |
|------|--------|-------------|
| **Owner** | Current Owner | Set curator, sentinels, transfer ownership |
| **Curator** | Owner | Timelocked: adapters, caps, allocators |
| **Allocator** | Curator | Allocate/deallocate capital, set liquidity adapter (Safe 1/3 multisig for Flagship) |
| **Sentinel** | Owner | Revoke pending timelocked actions |

## Timelock Requirements

Per Morpho listing rules:

| Duration | Actions |
|----------|---------|
| **7 days** | `increaseTimelock`, `removeAdapter`, `abdicate` |
| **3 days** | `addAdapter`, `increaseAbsoluteCap`, `increaseRelativeCap`, `setForceDeallocatePenalty` |

## Key Addresses (Mainnet)

```
# Tokens
USDS:    0xdC035D45d973E3EC169d2276DDab16f1e407384F
USDC:    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
USDT:    0xdAC17F958D2ee523a2206206994597C13D831ec7
stUSDS:  0x99CD4Ec3f88A45940936F469E4bB72A2A701EEB9
WETH:    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
wstETH:  0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
cbBTC:   0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf

# Chainlink Feeds
USDS/USD:  0xfF30586cD0F29eD462364C7e81375FC0C71219b1
USDC/USD:  0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
USDT/USD:  0x3E7d1eAB13ad0104d2750B8863b489D65364e32D

# Morpho Infrastructure
MORPHO_BLUE:      0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb
IRM_ADAPTIVE:     0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC
ADAPTER_REGISTRY: 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e
```

## Deployment Costs

| Vault | Gas (~ETH) | Tokens Needed |
|-------|------------|---------------|
| USDS Risk Capital | ~0.0015 ETH | 2 USDS, 2.1 stUSDS |
| USDC Risk Capital | ~0.0015 ETH | 2 USDC, 2.1 stUSDS |
| USDT Risk Capital | ~0.0015 ETH | 2 USDT, 2.1 stUSDS |
| USDT Savings | ~0.0015 ETH | 2 USDT, 2.1 stUSDS |
| Flagship Vault | ~0.003 ETH | ~4 USDS, 0.001 wstETH, 0.001 WETH, 0.0001 cbBTC |

## Troubleshooting

### "Out of gas" on Tenderly
USDS has complex transfer logic. Use `--gas-estimate-multiplier 200`.

### Test Failures
- Ensure Anvil is running before tests
- Run tests sequentially with `-j 1` if needed
- Create fresh fork for clean state

### Market Already Exists
Scripts handle this gracefully with try/catch. Safe to re-run.
