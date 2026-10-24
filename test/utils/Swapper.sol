// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Minimal swap router for tests and simulations: exact-input and exact-output swaps on
///         an ETH/token v4 pool, paying from and to `msg.sender`.
contract Swapper is IUnlockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager m) {
        manager = m;
    }

    struct Call {
        PoolKey key;
        bool zeroForOne;
        int256 amountSpecified;
        address payer;
    }

    /// @notice Buys with exactly `msg.value` ETH. Returns tokens received.
    function buy(PoolKey calldata key) external payable returns (uint256 out) {
        BalanceDelta d = _swap(key, true, -int256(msg.value), msg.sender);
        out = uint256(int256(d.amount1()));
    }

    /// @notice Buys exactly `amountOut` tokens; refunds unused ETH.
    function buyExactOut(PoolKey calldata key, uint256 amountOut) external payable returns (uint256 paid) {
        BalanceDelta d = _swap(key, true, int256(amountOut), msg.sender);
        paid = uint256(int256(-d.amount0()));
        if (msg.value > paid) SafeTransferLib.forceSafeTransferETH(msg.sender, msg.value - paid);
    }

    /// @notice Sells exactly `amountIn` tokens (pulled from the caller). Returns ETH received.
    function sell(PoolKey calldata key, uint256 amountIn) external returns (uint256 out) {
        BalanceDelta d = _swap(key, false, -int256(amountIn), msg.sender);
        out = uint256(int256(d.amount0()));
    }

    function sellExactOut(PoolKey calldata key, uint256 ethOut) external returns (uint256) {
        _swap(key, false, int256(ethOut), msg.sender);
        return 0;
    }

    function _swap(PoolKey calldata key, bool zeroForOne, int256 amount, address payer) internal returns (BalanceDelta d) {
        d = abi.decode(manager.unlock(abi.encode(Call(key, zeroForOne, amount, payer))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "pm");
        Call memory c = abi.decode(data, (Call));
        BalanceDelta d = manager.swap(
            c.key,
            SwapParams({
                zeroForOne: c.zeroForOne,
                amountSpecified: c.amountSpecified,
                sqrtPriceLimitX96: c.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) manager.settle{value: uint256(int256(-a0))}();
        if (a1 < 0) {
            manager.sync(c.key.currency1);
            SafeTransferLib.safeTransferFrom(Currency.unwrap(c.key.currency1), c.payer, address(manager), uint256(int256(-a1)));
            manager.settle();
        }
        if (a0 > 0) manager.take(c.key.currency0, c.payer, uint256(int256(a0)));
        if (a1 > 0) manager.take(c.key.currency1, c.payer, uint256(int256(a1)));
        return abi.encode(d);
    }

    receive() external payable {}
}
