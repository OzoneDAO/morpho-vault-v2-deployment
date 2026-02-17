/**
 * Pure allocation logic for the Flagship Vault Allocator Bot.
 *
 * Extracted from allocator.ts so it can be unit-tested without RPC or Safe dependencies.
 */

export interface AllocationAction {
  marketIndex: number;
  action: 'allocate' | 'deallocate';
  amount: bigint;
}

export interface AllocationInput {
  totalAssets: bigint;
  adapterAssets: bigint;
  perMarketAssets: bigint[];
  targetAllocatedPercent: number; // basis points, e.g. 2000 = 20%
  targetPerMarketPercent: number; // basis points, e.g. 500 = 5%
  rebalanceThresholdBps: number; // basis points, e.g. 100 = 1%
}

export interface AllocationResult {
  actions: AllocationAction[];
  skipped: boolean;
  reason?: string;
}

/**
 * Compute the allocation/deallocation actions needed to reach target per-market allocations.
 *
 * Cases handled:
 * 1. Within threshold  — no actions (deviation < rebalanceThresholdBps)
 * 2. Under-allocated   — allocate the deficit per market
 * 3. Over-allocated    — deallocate the excess per market
 * 4. Mixed             — some markets get allocations, others get deallocations
 * 5. Partial (bug fix) — only under-funded markets receive allocations;
 *                         markets already at target are skipped
 */
export function computeAllocationActions(input: AllocationInput): AllocationResult {
  const {
    totalAssets,
    adapterAssets,
    perMarketAssets,
    targetAllocatedPercent,
    targetPerMarketPercent,
    rebalanceThresholdBps,
  } = input;

  if (totalAssets === 0n) {
    return { actions: [], skipped: true, reason: 'totalAssets is zero' };
  }

  const targetTotalAllocated = (totalAssets * BigInt(targetAllocatedPercent)) / 10000n;
  const targetPerMarket = (totalAssets * BigInt(targetPerMarketPercent)) / 10000n;

  // Check if total deviation exceeds threshold
  const allocationDiff = adapterAssets > targetTotalAllocated
    ? adapterAssets - targetTotalAllocated
    : targetTotalAllocated - adapterAssets;

  const deviationBps = Number((allocationDiff * 10000n) / totalAssets);

  if (deviationBps < rebalanceThresholdBps) {
    return { actions: [], skipped: true, reason: 'within threshold' };
  }

  // Compute per-market actions based on actual on-chain balances
  const actions: AllocationAction[] = [];

  for (let i = 0; i < perMarketAssets.length; i++) {
    const current = perMarketAssets[i];

    if (current < targetPerMarket) {
      const diff = targetPerMarket - current;
      if (diff > 0n) {
        actions.push({ marketIndex: i, action: 'allocate', amount: diff });
      }
    } else if (current > targetPerMarket) {
      const excess = current - targetPerMarket;
      if (excess > 0n) {
        actions.push({ marketIndex: i, action: 'deallocate', amount: excess });
      }
    }
  }

  if (actions.length === 0) {
    return { actions: [], skipped: true, reason: 'all markets at target' };
  }

  return { actions, skipped: false };
}
