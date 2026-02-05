// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

/**
 * @title Constants
 * @notice Shared constants for Morpho Vault V2 deployments on Ethereum Mainnet
 */
library Constants {
    // ============ TOKENS ============

    // Loan Token
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    // Collateral Tokens
    address internal constant ST_USDS = 0x99CD4Ec3f88A45940936F469E4bB72A2A701EEB9;
    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // ============ PROTOCOL ADDRESSES ============

    address internal constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant IRM_ADAPTIVE = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    // ============ FACTORIES & REGISTRY ============

    address internal constant ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;
    address internal constant VAULT_V2_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address internal constant ADAPTER_FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;
    address internal constant ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;

    // ============ CHAINLINK PRICE FEEDS ============

    address internal constant CHAINLINK_CBBTC_USD = 0x2665701293fCbEB223D11A08D826563EDcCE423A;
    address internal constant CHAINLINK_STETH_USD = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address internal constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant CHAINLINK_USDS_USD = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;

    // Morpho wstETH/stETH exchange rate adapter (Chainlink-compatible interface)
    address internal constant MORPHO_WSTETH_STETH_ADAPTER = 0x905b7dAbCD3Ce6B792D874e303D336424Cdb1421;

    // ============ LLTV VALUES ============

    uint256 internal constant LLTV_STUSDS = 860000000000000000; // 86%
    uint256 internal constant LLTV_VOLATILE = 860000000000000000; // 86%

    // ============ TOKEN DECIMALS ============

    uint256 internal constant DECIMALS_USDS = 18;
    uint256 internal constant DECIMALS_STUSDS = 18;
    uint256 internal constant DECIMALS_CBBTC = 8;
    uint256 internal constant DECIMALS_WSTETH = 18;
    uint256 internal constant DECIMALS_WETH = 18;

    // ============ DEPLOYMENT PARAMS ============

    uint256 internal constant INITIAL_DEAD_DEPOSIT = 1e18; // 1 USDS
    uint256 internal constant MAX_RATE = 63419583967; // 200% APR
    uint256 internal constant TIMELOCK_LOW = 3 days;
    uint256 internal constant TIMELOCK_HIGH = 7 days;
}
