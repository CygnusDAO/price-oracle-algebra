// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

import { IERC20 } from "./IERC20.sol";

interface IHypervisor {
    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

    /// @return liquidity Amount of total liquidity in the base position
    /// @return amount0 Estimated amount of token0 that could be collected by
    /// burning the base position
    /// @return amount1 Estimated amount of token1 that could be collected by
    /// burning the base position
    function getBasePosition() external view returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function baseLower() external view returns (int24);

    function baseUpper() external view returns (int24);

    function limitLower() external view returns (int24);

    function limitUpper() external view returns (int24);

    function pool() external view returns (address);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function totalSupply() external view returns (uint256);
}
