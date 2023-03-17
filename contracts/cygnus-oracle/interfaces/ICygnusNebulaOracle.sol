// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IDexPair} from "./IDexPair.sol";
import {IERC20} from "./IERC20.sol";

/**
 *  @title ICygnusNebulaOracle Interface to interact with Cygnus' Chainlink oracle
 */
interface ICygnusNebulaOracle {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error PairIsInitialized Reverts when attempting to initialize an already initialized LP Token
     */
    error CygnusNebulaOracle__PairAlreadyInitialized(address lpTokenPair);

    /**
     *  @custom:error PairNotInitialized Reverts when attempting to get the price of an LP Token that is not initialized
     */
    error CygnusNebulaOracle__PairNotInitialized(address lpTokenPair);

    /**
     *  @custom:error MsgSenderNotAdmin Reverts when attempting to access admin only methods
     */
    error CygnusNebulaOracle__MsgSenderNotAdmin(address msgSender);

    /**
     *  @custom:error AdminCantBeZero Reverts when attempting to set the admin if the pending admin is the zero address
     */
    error CygnusNebulaOracle__AdminCantBeZero(address pendingAdmin);

    /**
     *  @custom:error PendingAdminAlreadySet Reverts when attempting to set the same pending admin twice
     */
    error CygnusNebulaOracle__PendingAdminAlreadySet(address pendingAdmin);

    /**
     *  @custom:error NebulaRecordNotInitialized Reverts when getting a record if not initialized
     */
    error CygnusNebulaOracle__NebulaRecordNotInitialized(IDexPair lpTokenPair);

    /**
     *  @custom:error NebulaRecordAlreadyInitialized Reverts when re-initializing a record
     */
    error CygnusNebulaOracle__NebulaRecordAlreadyInitialized(IDexPair lpTokenPair);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param initialized Whether or not the LP Token is initialized
     *  @param oracleId The ID for this oracle
     *  @param lpTokenPair The address of the LP Token
     *  @param priceFeedA The address of the Chainlink's aggregator contract for this LP Token's token0
     *  @param priceFeedB The address of the Chainlink's aggregator contract for this LP Token's token1
     *  @custom:event InitializeCygnusNebula Logs when an LP Token pair's price starts being tracked
     */
    event InitializeCygnusNebula(
        bool initialized,
        uint88 oracleId,
        address lpTokenPair,
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB
    );

    /**
     *  @param oracleCurrentAdmin The address of the current oracle admin
     *  @param oraclePendingAdmin The address of the pending oracle admin
     *  @custom:event NewNebulaPendingAdmin Logs when a new pending admin is set, to be accepted by admin
     */
    event NewOraclePendingAdmin(address oracleCurrentAdmin, address oraclePendingAdmin);

    /**
     *  @param oracleOldAdmin The address of the old oracle admin
     *  @param oracleNewAdmin The address of the new oracle admin
     *  @custom:event NewNebulaAdmin Logs when the pending admin is confirmed as the new oracle admin
     */
    event NewOracleAdmin(address oracleOldAdmin, address oracleNewAdmin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Returns the struct record of each oracle used by Cygnus
     *  @param lpTokenPair The address of the LP Token
     *  @return initialized Whether an LP Token is being tracked or not
     *  @return oracleId The ID of the LP Token tracked by the oracle
     *  @return underlying The address of the LP Token
     *  @return algebraPool The address of the Algebra Pool
     *  @return token0 Address of token0 from the LP
     *  @return token1 Address of token1 from the LP
     *  @return token0Decimals Decimals for token0
     *  @return token1Decimals Decimasl for token1
     *  @return priceFeedA The address of the Chainlink aggregator used for this LP Token's Token0
     *  @return priceFeedB The address of the Chainlink aggregator used for this LP Token's Token1
     */
    function getNebula(
        address lpTokenPair
    )
        external
        view
        returns (
            bool initialized,
            uint88 oracleId,
            address underlying,
            address algebraPool,
            IERC20 token0,
            IERC20 token1,
            uint256 token0Decimals,
            uint256 token1Decimals,
            AggregatorV3Interface priceFeedA,
            AggregatorV3Interface priceFeedB
        );

    /**
     *  @notice Gets the address of the LP Token that (if) is being tracked by this oracle
     *  @param id The ID of each LP Token that is being tracked by this oracle
     *  @return The address of the LP Token if it is being tracked by this oracle, else returns address zero
     */
    function allNebulas(uint256 id) external view returns (address);

    /**
     *  @return The name for this Cygnus-Chainlink Nebula oracle
     */
    function name() external view returns (string memory);

    /**
     *  @return The symbol for this Cygnus-Chainlink Nebula oracle
     */
    function symbol() external view returns (string memory);

    /**
     *  @return The address of the Cygnus admin
     */
    function admin() external view returns (address);

    /**
     *  @return The address of the new requested admin
     */
    function pendingAdmin() external view returns (address);

    /**
     *  @return The version of this oracle
     */
    function version() external view returns (string memory);

    /**
     *  @return SECONDS_PER_YEAR The number of seconds in year assumed by the oracle
     */
    function SECONDS_PER_YEAR() external view returns (uint256);

    /**
     *  @return How many LP Token pairs' prices are being tracked by this oracle
     */
    function nebulaSize() external view returns (uint24);

    /**
     *  @return The denomination token this oracle returns the price in
     */
    function denominationToken() external view returns (IERC20);

    /**
     *  @return The decimals for this Cygnus-Chainlink Nebula oracle
     */
    function decimals() external view returns (uint8);

    /**
     *  @return The address of Chainlink's denomination oracle
     */
    function denominationAggregator() external view returns (AggregatorV3Interface);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */
    /**
     *  @notice Get the annualized log APR given 2 exchange rates and the time elapsed between them
     *  @param exchangeRateLast The previous exchange rate
     *  @param exchangeRateNow The current exchange rate
     *  @param timeElapsed Time elapsed between the exchange rates
     *  @return apr The estimated APR
     */
    function getAnnualizedLogApr(
        uint256 exchangeRateLast,
        uint256 exchangeRateNow,
        uint256 timeElapsed
    ) external pure returns (uint256 apr);

    /**
     *  @return The price of the denomination token in USD. In our case it is USDC
     */
    function denominationPriceUsd() external view returns (uint256);

    /**
     *  @notice Gets the latest price of the LP Token's token0 and token1 denominated in denomination token
     *  @param lpTokenPair The address of the Gamma Vault
     *  @return tokenPriceA The price of the LP Token's token0 denominated in denomination token
     *  @return tokenPriceB The price of the LP Token's token1 denominated in denomination token
     */
    function assetPricesUsd(address lpTokenPair) external view returns (uint256 tokenPriceA, uint256 tokenPriceB);

    /**
     *  @notice Gets the latest price of the LP Token denominated in denomination token
     *  @notice LP Token pair must be initialized, else reverts with custom error
     *  @param lpTokenPair The address of the Gamma Vault
     *  @return lpTokenPrice The price of the LP Token denominated in denomination token
     */
    function lpTokenPriceUsd(address lpTokenPair) external view returns (uint256 lpTokenPrice);

    /**
     *  @notice Returns the total amounts of a gamma pool using the fair reserves of the position
     *  @param lpTokenPair The address of the Gamma Vault
     *  @return liquidity The liquidity amount in the limit position
     *  @return amount0 The amount of token0 in the limit position
     *  @return amount1 The amount of token1 in the limit position
     */
    function getLimitPosition(address lpTokenPair) external view returns (uint256 liquidity, uint256 amount0, uint256 amount1);

    /**
     *  @notice Returns the total amounts of a gamma pool using the fair reserves of the position
     *  @param lpTokenPair The address of the Gamma Vault
     *  @return liquidity The liquidity amount in the base position
     *  @return amount0 The amount of token0 in the base position
     *  @return amount1 The amount of token1 in the base position
     */
    function getBasePosition(address lpTokenPair) external view returns (uint256 liquidity, uint256 amount0, uint256 amount1);

    /**
     *  @notice Returns the total amounts of a gamma pool using the fair reserves of the position
     *  @param lpTokenPair The address of the Gamma Vault
     *  @return amount0 The amount of token1 in base position + limit position + balanceOf hypervisor
     *  @return amount1 The amount of token1 in base position + limit position + balanceOf hypervisor
     */
    function getTotalAmounts(address lpTokenPair) external view returns (uint256 amount0, uint256 amount1);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Initialize an LP Token pair, only admin
     *  @param lpTokenPair The address of the Gamma Vault
     *  @param priceFeedA The contract address of the Chainlink's aggregator contract for this Gamma Vault's token0
     *  @param priceFeedB The contract address of the Chainlink's aggregator contract for this Gamma Vault's token1
     *  @custom:security non-reentrant
     */
    function initializeNebula(address lpTokenPair, AggregatorV3Interface priceFeedA, AggregatorV3Interface priceFeedB) external;

    /**
     *  @notice Sets a new pending admin for the Oracle
     *  @param newOraclePendingAdmin Address of the requested Oracle Admin
     */
    function setOraclePendingAdmin(address newOraclePendingAdmin) external;

    /**
     *  @notice Sets a new admin for the Oracle
     */
    function setOracleAdmin() external;
}
