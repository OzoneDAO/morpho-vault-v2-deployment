# Flagship Vault Allocator Bot

A simple allocator bot for the Flagship USDS Vault V2 that maintains the 80% idle / 20% allocated strategy.

## Strategy

The bot allocates vault funds according to this strategy:
- **80% idle** - Kept in the vault for immediate withdrawal liquidity
- **20% allocated** - Split equally across 4 Morpho Blue markets:
  - stUSDS/USDS (5%)
  - cbBTC/USDS (5%)
  - wstETH/USDS (5%)
  - WETH/USDS (5%)

## Prerequisites

- Node.js >= 18.0.0
- The bot's address must be set as an **Allocator** on the vault
- Deployed vault and adapter addresses from the deployment script

## Setup

1. Install dependencies:
   ```bash
   cd bot
   npm install
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

3. Required environment variables:

   **From your setup:**
   - `RPC_URL` - Ethereum RPC endpoint
   - `PRIVATE_KEY` - Allocator's private key (EOA recommended per BA Labs)

   **From DeployFlagshipVaultV2 output:**
   - `VAULT_ADDRESS` - Flagship Vault V2 address
   - `ADAPTER_ADDRESS` - MorphoMarketV1AdapterV2 address
   - `ORACLE_CBBTC` - cbBTC/USDS oracle address
   - `ORACLE_WSTETH` - wstETH/USDS oracle address
   - `ORACLE_WETH` - WETH/USDS oracle address

   **Pre-configured (existing deployment):**
   - `ORACLE_STUSDS` - Already defaults to `0x0A976226d113B67Bd42D672Ac9f83f92B44b454C`

   **Optional (correct defaults provided):**
   - `LLTV_*` - All default to 86% (860000000000000000) per BA Labs recommendation
   - `DRY_RUN` - Set to `true` for simulation mode

## Usage

### Manual Run

```bash
# Development (uses tsx)
npm run dev

# Production (compile first)
npm run build
npm start
```

### Dry Run Mode

Set `DRY_RUN=true` in `.env` to simulate without executing transactions:
```bash
DRY_RUN=true npm run dev
```

### Cronjob Setup

Run every hour to maintain allocation:
```bash
# Edit crontab
crontab -e

# Add this line (adjust paths as needed)
0 * * * * cd /path/to/morpho-vault-v2-deployment/bot && /usr/bin/npm run allocate >> /var/log/vault-allocator.log 2>&1
```

## How It Works

1. **Check permissions** - Verifies the bot is an allocator
2. **Read current state** - Gets total assets, allocated amounts, idle balance
3. **Calculate targets** - Determines target allocation per market (5% each)
4. **Check threshold** - Only rebalances if deviation exceeds 1%
5. **Execute transactions** - Calls `vault.allocate()` or `vault.deallocate()` as needed
6. **Log results** - Reports final state

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `targetIdlePercent` | 80% | Target idle percentage |
| `targetPerMarketPercent` | 5% | Target per market |
| `rebalanceThresholdBps` | 1% | Min deviation to trigger rebalance |
| `minAllocationAmount` | 100 USDS | Min amount to allocate (avoids dust) |

## Security Notes

- **Never commit `.env`** - Contains private key
- **Use a dedicated allocator key** - Separate from owner/curator
- **Monitor the bot** - Check logs regularly
- **Test with DRY_RUN first** - Verify logic before live execution

## Extending for Dynamic Weights

To implement price-based dynamic allocation:

1. Add Chainlink price feed reads
2. Calculate weights based on price/volatility
3. Adjust `targetPerMarket` per asset
4. Ensure total still respects 20% cap

Example modification point in `allocator.ts`:
```typescript
// Replace fixed weights with dynamic calculation
const weights = await calculateDynamicWeights(publicClient);
const targetPerMarket = (targetTotalAllocated * weights[market.name]) / 10000n;
```

## Troubleshooting

### "Account is not an allocator"
The bot's address must be set as allocator by the curator:
```solidity
vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, botAddress, true));
vault.setIsAllocator(botAddress, true);
```

### "Allocation exceeds cap"
The vault has 5% relative cap per market. If you're hitting this:
- Check if there are existing allocations
- Reduce allocation amount
- Or increase caps via curator (timelocked)

### Transaction reverts
Common causes:
- Insufficient idle balance
- Oracle address incorrect
- Market doesn't exist (needs to be created first)
