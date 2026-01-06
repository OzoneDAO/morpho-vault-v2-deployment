# Morpho Vault V2 Deployment

This project contains Foundry scripts and tests for deploying and configuring a **Morpho Vault V2 (USDC)** on **Morpho Market V1 (USDC/stUSDS)**.

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
# Run integration tests (requires mainnet fork)
forge test --match-contract DeployScriptTest --fork-url <RPC_URL> -vvvv

# Example with local anvil/localhost
forge test --match-contract DeployScriptTest --fork-url http://localhost:8545 -vvvv
```

## Deployment

To deploy the Vault V2 to Mainnet (or a testnet):

1. Set your `PRIVATE_KEY` environment variable.
2. Run the deployment script.

```shell
forge script script/DeployUSDCVaultV2.s.sol:DeployUSDCVaultV2 \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify \
  --etherscan-api-key <ETHERSCAN_KEY>
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
