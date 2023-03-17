# Cygnus LP Oracle - Concentrated Liquidity

A fair reserves LP Oracle for concentrated liquidity pools such as UniswapV3 or Algebra.

We calculate the `sqrtPriceX96` from our oracles and then derive the pool's fair reserves from the price.

```solidity
sqrtPriceX96 = sqrt(token1 / token0) * 2^96
             = sqrt((p0 * 10**decimals1) / (p1 * 10**decimals0)) * 2^96
             = sqrt((p0 * 10**decimals1) / (p1 * 10**decimals0)) * 2^48 * 2^48
             = sqrt((p0 * 10**decimals1 * 2^96) / (p1 * 10**decimals0)) * 2^48
```
