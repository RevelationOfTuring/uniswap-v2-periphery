pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '../libraries/UniswapV2OracleLibrary.sol';
import '../libraries/UniswapV2Library.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract ExampleOracleSimple {
    using FixedPoint for *;

    // 合约规定，两次update之间的时间间隔不能小于24小时
    uint public constant PERIOD = 24 hours;

    // pair地址
    IUniswapV2Pair immutable pair;
    // token0地址
    address public immutable token0;
    // token1地址
    address public immutable token1;

    // 记录上一次update后的token0的价格累计和
    uint    public price0CumulativeLast;
    // 记录上一次update后的token1的价格累计和
    uint    public price1CumulativeLast;
    // 记录上一次update的时间戳
    uint32  public blockTimestampLast;
    // 本次update与上一次update之间的token0的TWAP
    FixedPoint.uq112x112 public price0Average;
    // 本次update与上一次update之间的token1的TWAP
    FixedPoint.uq112x112 public price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'ExampleOracleSimple: NO_RESERVES'); // ensure that there's liquidity in the pair
    }

    // 用于更新使用合约的内部记录时间及price0Cumulative的状态变量
    function update() external {
        // 获取当前距离最近一次pair swap的时间间隔，及price0和price1的累计和
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
                            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        // 计算当前时间戳与上一次执行update时的时间戳之间的时间价格（计算允许溢出）
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        // 确保两次update之间的时间间隔大于等于间隔要求PERIOD
        require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        // token0在这段period的TWAP为t_now~t0的price0累计和 - t_{pre_update}~t0的price0累计和，再除以两次update之间的时间间隔（印证上述公式）
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        // token1在这段period的TWAP为t_now~t0的price1累计和 - t_{pre_update}~t0的price1累计和，再除以两次update之间的时间间隔（印证上述公式）
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        // 将本次price0Cumulative、price1CumulativeLast和blockTimestamp持久化到当前使用合约中
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    // 输入目标token和对应数量，返回该数量基于对应TWAP的价值(用另外的一种token的数量表示)
    function consult(address token, uint amountIn) external view returns (uint amountOut) {
        if (token == token0) {
            // 如果是token0，返回price0Average*amountIn的整数部分
            // 注:返回price0Average为FixedPoint.uq112x112，即用低112位表示小数，高112位表示整数。
            // price0Average.mul(amountIn)的返回值为uq144x112，即用低112位表示小数，高144位表示整数
            // .decode144()的作用是将price0Average.mul(amountIn)的结果右移112位，即取其整数部分
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            // 如果是token1。如果既不是token0也部署token1，会revert
            require(token == token1, 'ExampleOracleSimple: INVALID_TOKEN');
            // 返回price1Average*amountIn的整数部分
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
