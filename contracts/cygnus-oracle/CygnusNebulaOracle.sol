// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import {ICygnusNebulaOracle} from "./interfaces/ICygnusNebulaOracle.sol";
import {Context} from "./utils/Context.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {ERC20Normalizer} from "./utils/ERC20Normalizer.sol";

// Libraries
import {TickMath} from "./libraries/TickMath.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {PRBMath, PRBMathUD60x18} from "./libraries/PRBMathUD60x18.sol";

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {IHypervisor} from "./interfaces/IHypervisor.sol";
import {IAlgebraPoolState} from "./interfaces/IAlgebraPoolState.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 *  @title  CygnusNebulaOracle
 *  @author CygnusDAO
 *  @notice Oracle used by Cygnus that returns the price of 1 LP Token in the denomination token. In case need
 *          different implementation just update the denomination variable `denominationAggregator`
 *          and `denominationToken` with token
 *  @notice Gamma LP Oracle implementation based on concentrated liquidity positions.
 *          We derive the sqrtPriceX96 from chainlink oracles ourselves in the function `lpTokenPriceUsd`. We do this
 *          to get the fair reserves amount from the position instead of querying the square root price from the pool
 *          itself, avoiding price manipulation.`
 *
 *          First we calculate the sqrt price given asset prices:
 *
 *          sqrtPriceX96 = sqrt(token1/token0) * 2^96                                 [From Uniswap's definition]
 *                       = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^96
 *                       = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^48 * 2^48
 *                       = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
 *
 *          Then we get reserves = base amounts + limit abouts + balanceOf hypervisor given our sqrtPrice. Finally:
 *          Token Price  = TVL / Token Supply = (r0 * p0 + r1 * p1) / totalSupply
 */
contract CygnusNebulaOracle is ICygnusNebulaOracle, Context, ReentrancyGuard, ERC20Normalizer {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Arithmetic library with operations for fixed-point numbers
     */
    using PRBMathUD60x18 for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @custom:struct CygnusNebula Official record of all Chainlink oracles used by Cygnus
     *  @custom:member initialized Whether an LP Token is being tracked or not
     *  @custom:member oracleId The ID of the LP Token tracked by the oracle
     *  @custom:member underlying The address of the LP Token (vault token)
     *  @custom:member algebraPool The pool for the underlying LP token
     *  @custom:member token0 The address of token0 from the LP token
     *  @custom:member token1 The address of token1 from the LP token
     *  @custom:member token0Decimals The decimals of token0 from the LP token
     *  @custom:member token1Decimals The decimals of token1 from the LP token
     *  @custom:member priceFeedA The address of the Chainlink aggregator for token0
     *  @custom:member priceFeedB The address of the Chainlink aggregator for token1
     */
    struct CygnusNebula {
        bool initialized;
        uint88 oracleId;
        address underlying;
        address algebraPool;
        IERC20 token0;
        IERC20 token1;
        uint256 token0Decimals;
        uint256 token1Decimals;
        AggregatorV3Interface priceFeedA;
        AggregatorV3Interface priceFeedB;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    mapping(address => CygnusNebula) public override getNebula;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override name = "Cygnus-Nebula: Gamma LP Oracle";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override symbol = "CygNebula";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    uint256 public constant override SECONDS_PER_YEAR = 31536000;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    IERC20 public immutable override denominationToken;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    uint8 public immutable override decimals;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    AggregatorV3Interface public immutable override denominationAggregator;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address public override admin;

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Oracle
     *  @param denomination The denomination token, used to get the decimals that this oracle retursn the price in.
     *         ie If denomination token is USDC, the oracle will return the price in 6 decimals, if denomination
     *         token is DAI, the oracle will return the price in 18 decimals.
     *  @param denominationPrice The denomination token this oracle returns the prices in
     */
    constructor(IERC20 denomination, AggregatorV3Interface denominationPrice) {
        // Assign admin
        admin = _msgSender();

        // Denomination token
        denominationToken = denomination;

        // Decimals for the oracle based on the denomination token
        decimals = denomination.decimals();

        // Assign the denomination the LP Token will be priced in
        denominationAggregator = denominationPrice;

        // Cache scalar of denom token price
        computeScalar(IERC20(address(denominationPrice)));
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for admin control only 👽
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admin control only 👽
     */
    function isCygnusAdmin() internal view {
        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (_msgSender() != admin) {
            revert CygnusNebulaOracle__MsgSenderNotAdmin(_msgSender());
        }
    }

    /**
     *  @notice The decimals are always normalized to 18
     *  @notice returns the sqrt price given 2 asset prices.
     *  @notice sqrtPriceX96 = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
     */
    function getSqrtPriceX96Internal(
        uint256 priceA,
        uint256 decimalsA,
        uint256 priceB,
        uint256 decimalsB
    ) internal pure returns (uint160) {
        // Return price given assets and decimals
        return uint160(PRBMath.sqrt((priceA * (10 ** decimalsB) * (1 << 96)) / (priceB * (10 ** decimalsA))) << 48);
    }

    /**
     *  @notice Get the amounts of the given numbers of liquidity tokens
     *  @param tickLower The lower tick of the position
     *  @param tickUpper The upper tick of the position
     *  @param liquidity The amount of liquidity tokens
     *  @return Amount of token0 and token1
     */
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    /**
     *  @notice Get the info of the given position
     *  @param lpTokenPair The address of the Gamma Vault
     *  @param tickLower The lower tick of the position
     *  @param tickUpper The upper tick of the position
     *  @param pool The address of the Algebra Pool for the Gamma Vault
     *  @return liquidity The amount of liquidity of the position
     *  @return tokensOwed0 Amount of token0 owed
     *  @return tokensOwed1 Amount of token1 owed
     */
    function algebraPosition(
        address lpTokenPair,
        int24 tickLower,
        int24 tickUpper,
        address pool
    ) internal view returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1) {
        // Algebra position key
        bytes32 positionKey;

        assembly {
            positionKey := or(shl(24, or(shl(24, lpTokenPair), and(tickLower, 0xFFFFFF))), and(tickUpper, 0xFFFFFF))
        }

        // Return liquidity and reserves
        (liquidity, , , , tokensOwed0, tokensOwed1) = IAlgebraPoolState(pool).positions(positionKey);
    }

    /**
     *  @notice Get the base position from the Gamma Vault with our sqrtPrice
     *  @param cygnusNebula The struct of the gamma vault
     *  @param sqrtPriceX96 The square root price calculated using Chainlink oracles
     *  @return liquidity The amount of liquidity of the position
     *  @return amount0 Amount of token0 owed
     *  @return amount1 Amount of token1 owed
     */
    function getLimitPositionInternal(
        CygnusNebula memory cygnusNebula,
        uint160 sqrtPriceX96
    ) internal view returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        // Limit lower tick
        int24 limitLower = IHypervisor(cygnusNebula.underlying).limitLower();

        // Limit upper tick
        int24 limitUpper = IHypervisor(cygnusNebula.underlying).limitUpper();

        // Get the position given the ranges
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = algebraPosition(
            cygnusNebula.underlying,
            limitLower,
            limitUpper,
            cygnusNebula.algebraPool
        );

        // Compute amounts for liquidity based on our sqrtPrice
        (amount0, amount1) = getAmountsForLiquidity(sqrtPriceX96, limitLower, limitUpper, positionLiquidity);

        // Amount of token0 in limit position
        amount0 += tokensOwed0;

        // Amount of token1 in limit position
        amount1 += tokensOwed1;

        // Liquidity in limit position
        liquidity = positionLiquidity;
    }

    /**
     *  @notice Get the base position from the Gamma Vault with our sqrtPrice
     *  @param cygnusNebula The struct of the gamma vault
     *  @param sqrtPriceX96 The square root price calculated using Chainlink oracles
     *  @return liquidity The amount of liquidity of the position
     *  @return amount0 Amount of token0 owed
     *  @return amount1 Amount of token1 owed
     */
    function getBasePositionInternal(
        CygnusNebula memory cygnusNebula,
        uint160 sqrtPriceX96
    ) internal view returns (uint256 liquidity, uint256 amount0, uint256 amount1) {
        // Limit lower tick
        int24 baseLower = IHypervisor(cygnusNebula.underlying).baseLower();

        // Limit upper tick
        int24 baseUpper = IHypervisor(cygnusNebula.underlying).baseUpper();

        // Get the position given the ranges
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = algebraPosition(
            cygnusNebula.underlying,
            baseLower,
            baseUpper,
            cygnusNebula.algebraPool
        );

        // Compute amounts for liquidity based on our sqrtPrice
        (amount0, amount1) = getAmountsForLiquidity(sqrtPriceX96, baseLower, baseUpper, positionLiquidity);

        // Amount of token0
        amount0 += tokensOwed0;

        // Amount of token1
        amount1 += tokensOwed1;

        // Liquidity tokens
        liquidity = positionLiquidity;
    }

    /**
     *  @notice Get total amounts given a stored pair and a price
     *  @param cygnusNebula Struct of the LP Token pair
     *  @param sqrtPriceX96 The pre-computed sqrtPriceX96
     *  @return total0 The total amount of token0 in the position
     *  @return total1 The total amount of token1 in the position
     */
    function getTotalAmountsInternal(
        CygnusNebula memory cygnusNebula,
        uint160 sqrtPriceX96
    ) internal view returns (uint256 total0, uint256 total1) {
        // Get base position
        (, uint256 base0, uint256 base1) = getBasePositionInternal(cygnusNebula, sqrtPriceX96);

        // Get limit position
        (, uint256 limit0, uint256 limit1) = getLimitPositionInternal(cygnusNebula, sqrtPriceX96);

        // Total0 = base0 + limit0 + hypervisors balance of token0
        total0 = cygnusNebula.token0.balanceOf(cygnusNebula.underlying) + base0 + limit0;

        // Total1 = base1 + limit1 + hypervisors balance of token1
        total1 = cygnusNebula.token1.balanceOf(cygnusNebula.underlying) + base1 + limit1;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function nebulaSize() public view override returns (uint24) {
        // Return how many LP Tokens we are tracking
        return uint24(allNebulas.length);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getAnnualizedLogApr(
        uint256 exchangeRateLast,
        uint256 exchangeRateNow,
        uint256 timeElapsed
    ) external pure override returns (uint256) {
        // Get the natural logarithm of last exchange rate
        uint256 logRateYesterday = exchangeRateLast.ln();

        // Get the natural logarithm of current exchange rate
        uint256 logRateToday = exchangeRateNow.ln();

        // Get the log rate difference
        uint256 logRateDiff = logRateToday - logRateYesterday;

        // The log APR is = (lorRateDif * 1 year) / time since last update
        uint256 logAprInYear = (logRateDiff * SECONDS_PER_YEAR) / timeElapsed;

        // Get the natural exponent of the log APR and substract 1
        uint256 annualizedApr = logAprInYear.exp() - 1e18;

        // Returns the annualized APR, taking into account time since last update
        return annualizedApr;
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function denominationPriceUsd() external view override returns (uint256) {
        // Chainlink price feed for the LP denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Return price without adjusting decimals - not used by this contract, we keep it here to quickly check
        // in case Circle rugz
        return uint256(latestRoundUsd);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function assetPricesUsd(
        address lpTokenPair
    ) external view override returns (uint256 tokenPriceA, uint256 tokenPriceB) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Chainlink price feed for this lpTokens token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Chainlink price feed for this lpTokens token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // Chainlink price feed for denomination token
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust price to 18 decimals
        uint256 adjustedUsdPrice = normalize(IERC20(address(denominationAggregator)), uint256(latestRoundUsd));

        // Return token0's price in denom token and decimals
        tokenPriceA = adjustedPriceA.div(adjustedUsdPrice) / (10 ** (18 - decimals));

        // Return token1's price in denom token and decimals
        tokenPriceB = adjustedPriceB.div(adjustedUsdPrice) / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function lpTokenPriceUsd(address lpTokenPair) external view override returns (uint256 lpTokenPrice) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair is initialized
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get price of the assets from Chainlink; token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Price token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // 2. Get the sqrtPrice given asset prices and decimal of assets (stored when initialized)
        // sqrtPriceX96 = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
        uint160 sqrtPriceX96 = getSqrtPriceX96Internal(
            adjustedPriceA,
            cygnusNebula.token0Decimals,
            adjustedPriceB,
            cygnusNebula.token1Decimals
        );

        // 3. Get the fair reserves of token0 and token1 given our sqrtPricex96
        (uint256 reservesTokenA, uint256 reservesTokenB) = getTotalAmountsInternal(cygnusNebula, sqrtPriceX96);

        // Adjust reserves Token A
        uint256 adjustedReservesA = normalize(cygnusNebula.token0, reservesTokenA);

        // Adjust reserves Token B
        uint256 adjustedReservesB = normalize(cygnusNebula.token1, reservesTokenB);

        // 4. Get the total Supply of LP
        uint256 totalSupply = IHypervisor(lpTokenPair).totalSupply();

        // 5. Token Price = TVL / Token Supply = (r0 * p0 + r1 * p1) / totalSupply
        uint256 priceUsd = (adjustedReservesA * adjustedPriceA + adjustedReservesB * adjustedPriceB) / totalSupply;

        // 6. Return the token price in denomination token (in our case USDC)
        (, int256 latestRoundUsd, , , ) = denominationAggregator.latestRoundData();

        // Adjust denomination price to 18 decimals
        uint256 adjustedUsdcPrice = normalize(IERC20(address(denominationAggregator)), uint256(latestRoundUsd));

        // Adjust for denom token decimals
        lpTokenPrice = priceUsd.div(adjustedUsdcPrice) / (10 ** (18 - decimals));
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getLimitPosition(
        address lpTokenPair
    ) external view override returns (uint256 liquidity, uint256 total0, uint256 total1) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Get price from Chainlink for token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Price Token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        //  sqrtPriceX96
        uint160 sqrtPriceX96 = getSqrtPriceX96Internal(
            adjustedPriceA,
            cygnusNebula.token0Decimals,
            adjustedPriceB,
            cygnusNebula.token1Decimals
        );

        // Return liquidity and total amounts of limit position
        return getLimitPositionInternal(cygnusNebula, sqrtPriceX96);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getBasePosition(
        address lpTokenPair
    ) external view override returns (uint256 liquidity, uint256 total0, uint256 total1) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // Get price from Chainlink for token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Price Token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // sqrtPriceX96
        uint160 sqrtPriceX96 = getSqrtPriceX96Internal(
            adjustedPriceA,
            cygnusNebula.token0Decimals,
            adjustedPriceB,
            cygnusNebula.token1Decimals
        );

        // Return liquidity and total amounts of base position
        return getBasePositionInternal(cygnusNebula, sqrtPriceX96);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     */
    function getTotalAmounts(address lpTokenPair) external view override returns (uint256 total0, uint256 total1) {
        // Load to memory
        CygnusNebula memory cygnusNebula = getNebula[lpTokenPair];

        /// custom:error PairNotInitialized Avoid getting price unless lpTokenPair's price is being tracked
        if (!cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairNotInitialized(lpTokenPair);
        }

        // 1. Get price from Chainlink for token0
        (, int256 priceA, , , ) = cygnusNebula.priceFeedA.latestRoundData();

        // Price Token1
        (, int256 priceB, , , ) = cygnusNebula.priceFeedB.latestRoundData();

        // Adjust price Token A to 18 decimals
        uint256 adjustedPriceA = normalize(IERC20(address(cygnusNebula.priceFeedA)), uint256(priceA));

        // Adjust price Token B to 18 decimals
        uint256 adjustedPriceB = normalize(IERC20(address(cygnusNebula.priceFeedB)), uint256(priceB));

        // sqrtPriceX96
        uint160 sqrtPriceX96 = getSqrtPriceX96Internal(
            adjustedPriceA,
            cygnusNebula.token0Decimals,
            adjustedPriceB,
            cygnusNebula.token1Decimals
        );

        // Base + Limit + Balance of Hypervisor
        return getTotalAmountsInternal(cygnusNebula, sqrtPriceX96);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function initializeNebula(
        address lpTokenPair,
        AggregatorV3Interface aggregatorA,
        AggregatorV3Interface aggregatorB
    ) external override nonReentrant cygnusAdmin {
        // Load to storage
        CygnusNebula storage cygnusNebula = getNebula[lpTokenPair];

        /// @custom:error PairIsinitialized Avoid duplicate oracle
        if (cygnusNebula.initialized) {
            revert CygnusNebulaOracle__PairAlreadyInitialized(lpTokenPair);
        }

        // Get total length and assign new id
        cygnusNebula.oracleId = nebulaSize();

        // Store LP Token address
        cygnusNebula.underlying = lpTokenPair;

        // Store the algebra pool this lp token represents
        cygnusNebula.algebraPool = IHypervisor(lpTokenPair).pool();

        // Store underlying tokens for the pair; token0
        cygnusNebula.token0 = IHypervisor(lpTokenPair).token0();

        // Token1
        cygnusNebula.token1 = IHypervisor(lpTokenPair).token1();

        // Cache scalars; token0
        computeScalar(cygnusNebula.token0);

        // token1
        computeScalar(cygnusNebula.token1);

        // Store token decimals, needed to compute sqrtPriceX96; token0
        cygnusNebula.token0Decimals = cygnusNebula.token0.decimals();

        // token1
        cygnusNebula.token1Decimals = cygnusNebula.token1.decimals();

        // Store Chainlink oracle aggregators; token0
        cygnusNebula.priceFeedA = aggregatorA;

        // token1
        cygnusNebula.priceFeedB = aggregatorB;

        // Cache scalars; token0
        computeScalar(IERC20(address(aggregatorA)));

        // token1
        computeScalar(IERC20(address(aggregatorB)));

        // Add to list
        allNebulas.push(lpTokenPair);

        // Store oracle status
        cygnusNebula.initialized = true;

        /// @custom:event InitializeCygnusNebula
        emit InitializeCygnusNebula(true, cygnusNebula.oracleId, lpTokenPair, aggregatorA, aggregatorB);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function setOraclePendingAdmin(address newPendingAdmin) external override nonReentrant cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == pendingAdmin) {
            revert CygnusNebulaOracle__PendingAdminAlreadySet(newPendingAdmin);
        }

        // Assign address of the requested admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewOraclePendingAdmin(admin, newPendingAdmin);
    }

    /**
     *  @inheritdoc ICygnusNebulaOracle
     *  @custom:security non-reentrant only-admin
     */
    function setOracleAdmin() external override nonReentrant cygnusAdmin {
        /// @custom:error AdminCantBeZero Avoid settings the admin to the zero address
        if (pendingAdmin == address(0)) {
            revert CygnusNebulaOracle__AdminCantBeZero(pendingAdmin);
        }

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Assign new admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewOracleAdmin
        emit NewOracleAdmin(oldAdmin, admin);
    }
}
