// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";
import {EngineToken} from "../../src/token/EngineToken.sol";
import {EngineHook} from "../../src/token/EngineHook.sol";
import {ProtocolLiquidity} from "../../src/token/ProtocolLiquidity.sol";
import {Swapper} from "./Swapper.sol";

contract FeeSink {
    uint256 public received;

    function receiveTradingFees() external payable {
        received += msg.value;
    }

    receive() external payable {}
}

/// @notice A local canonical v4 PoolManager, ENGINE, the fee hook at a flag-encoded address and the
///         protocol liquidity seeded with `marketEth` and `marketTokens`.
abstract contract MarketFixture is Test {
    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    IPoolManager internal manager;
    EngineToken internal token;
    EngineHook internal hook;
    ProtocolLiquidity internal liquidity;
    Swapper internal swapper;
    FeeSink internal treasurySink;
    address internal operator = makeAddr("operator");
    PoolKey internal key;

    function _deployMarket(uint256 marketEth, uint256 marketTokens, uint256 otherTokens, address otherHolder) internal {
        manager = IPoolManager(deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this))));
        address[] memory to = new address[](otherTokens == 0 ? 1 : 2);
        uint256[] memory amounts = new uint256[](to.length);
        to[0] = address(this);
        amounts[0] = marketTokens;
        if (otherTokens != 0) {
            to[1] = otherHolder;
            amounts[1] = otherTokens;
        }
        token = new EngineToken(to, amounts);
        address hookAddr = address((uint160(uint256(keccak256("draw-shapes.hook"))) & ~uint160(0x3fff)) | HOOK_FLAGS);
        liquidity = new ProtocolLiquidity(manager, address(token), hookAddr, address(this));
        treasurySink = new FeeSink();
        deployCodeTo(
            "EngineHook.sol:EngineHook",
            abi.encode(manager, address(token), address(liquidity), address(this), operator, address(treasurySink), uint16(200), uint16(25)),
            hookAddr
        );
        hook = EngineHook(payable(hookAddr));
        hook.setFeeExempt(address(liquidity), true);
        token.transfer(address(liquidity), marketTokens);
        liquidity.launch{value: marketEth}(_sqrtPrice(marketTokens, marketEth));
        key = liquidity.poolKey();
        swapper = new Swapper(manager);
    }

    /// @dev sqrtPriceX96 for a price of `tokens / eth` (currency1 per currency0).
    function _sqrtPrice(uint256 tokens, uint256 eth) internal pure returns (uint160) {
        return uint160(FP.sqrt(FP.fullMulDiv(tokens, 1 << 192, eth)));
    }

    function _buy(address who, uint256 eth) internal returns (uint256 out) {
        vm.prank(who);
        out = swapper.buy{value: eth}(key);
    }

    function _sell(address who, uint256 amount) internal returns (uint256 out) {
        vm.startPrank(who);
        token.approve(address(swapper), amount);
        out = swapper.sell(key, amount);
        vm.stopPrank();
    }
}
