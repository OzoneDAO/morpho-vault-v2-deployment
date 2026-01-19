# Morpho Vault V2 Deployment

This project contains Foundry scripts and tests for deploying and configuring a **Morpho Vault V2 (USDS)** on **Morpho Market V1 (USDS/stUSDS)**.

## Installation

Ensure you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

```shell
forge install
```

## Testing

Run the integration and deployment tests against a mainnet fork.

**Prerequisites:**
- You need an RPC URL (e.g., Alchemy, Infura) or a local Ethereum node.
- The tests mock the `PRIVATE_KEY` for simulation.

```shell
source .env

# before vault deployment
anvil --fork-url $RPC_URL
forge test --match-contract DeployScriptTest --fork-url http://localhost:8545 -vvvv

# after vault deployment (with VAULT_ADDRESS in .env)
anvil --fork-url $RPC_URL
forge test --match-contract DeployedVaultTest --fork-url http://localhost:8545 -vvvv
```

## Deployment

To deploy the Vault V2 to Mainnet (or a testnet):

1. Set your `PRIVATE_KEY` environment variable.
2. Run the deployment script.

```shell
source .env
forge script script/DeployUSDSVaultV2.s.sol:DeployUSDSVaultV2 \
  --rpc-url $RPC_URL \
  --broadcast \
  --slow \
  --gas-estimate-multiplier 200 \
  -vvvv
```

## Configuration & Roles

The deployment script supports optional environment variables to configure the final roles of the Vault. If these are not set, they default to the `deployer` address (except `SENTINEL` which defaults to `address(0)`).

### Roles
- **OWNER**: The ultimate owner of the Vault. Can set other roles.
- **CURATOR**: Responsible for managing the Vault configuration (caps, adapters, etc.) via a timelock.
- **ALLOCATOR**: Responsible for rebalancing funds between adapters and managing the liquidity adapter.
- **SENTINEL**: A guardian role that can revoke timelocked actions or pause certain functionalities.

### Environment Variables
Set these in your `.env` file or export them in your shell:

```bash
export OWNER=0x...
export CURATOR=0x...
export ALLOCATOR=0x...
export SENTINEL=0x...
```
