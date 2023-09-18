> :warning: **All CygnusDAO oracles have been moved to a single oracle repository which contains the oracles and the oracle registry. For all oracles see <a href="https://github.com/CygnusDAO/cygnus-oracles">here</a>**.

# Cygnus LP Oracle - Concentrated Liquidity

A fair reserves LP Oracle for Algebra concentrated liquidity pools.

We calculate the `sqrtPriceX96` from our oracles and then derive the pool's fair reserves from the price. Modified from MakerDAO:

https://github.com/makerdao/univ3-lp-oracle/blob/master/src/GUniLPOracle.sol

```solidity
sqrtPriceX96 = sqrt(token1 / token0) * 2^96
             = sqrt((p0 * 10**decimals1) / (p1 * 10**decimals0)) * 2^96
             = sqrt((p0 * 10**decimals1) / (p1 * 10**decimals0)) * 2^48 * 2^48
             = sqrt((p0 * 10**decimals1 * 2^96) / (p1 * 10**decimals0)) * 2^48
```
