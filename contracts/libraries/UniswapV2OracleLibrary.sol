pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        // 当前时间戳
        blockTimestamp = currentBlockTimestamp();
        // pair中对应记录的token0的累计价格值
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        // pair中对应记录的token1的累计价格值
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        // 获取pair中上一次swap后的x,y和时间戳
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            // 如果pair内最近一次swap的时间戳不等于当前时间戳，说明swap后到现在存在时间流逝
            // 计算当前时间距离最近一次swap的时间间隔
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            // FixedPoint.fraction(reserve1, reserve0)._x为当前pair中token0的价格, 将它乘以时间间隔追加到price0Cumulative上
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            // FixedPoint.fraction(reserve0, reserve1)._x为当前pair中token1的价格, 将它乘以时间间隔追加到price1Cumulative上
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}
