// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IPrizeCollection {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IShapesRedeem {
    function redeemBatch(uint256[] calldata tokenIds) external returns (uint256 totalWei);
}

interface IPacksRedeem {
    function redeem(uint256 packId) external;
}

interface IDrawEngineBuy {
    function acquireBatch(
        address purchaser,
        address referrer,
        uint256 count,
        uint256 maxAcquisitionFee,
        uint256 minWeightedValue,
        uint256 maxNegativeSlippageBps,
        uint256 expectedInventoryVersion,
        uint256 deadline
    ) external payable returns (uint256[] memory requestIds);
}

/// @title PrizeRouter
/// @notice Lets a player play their winnings: redeem selected Shapes and Draw Packs at face value
///         and pull with that ETH (plus any ETH sent) in one transaction, or cash them out in one
///         transaction. Stateless: it holds prizes and ETH only within a call, and returns all change
///         to the caller. Each collection needs one `setApprovalForAll(router, true)` from the player.
/// @dev Redemption pays only the owner, so the router takes each prize from the caller with the
///      caller's approval, redeems it as owner and spends or forwards the ETH before returning.
///      Every amount is measured as a balance delta, so ETH forced into the router is never spent
///      for anyone and never blocks a call.
contract PrizeRouter is ReentrancyGuard {
    IDrawEngineBuy public immutable engine;
    address public immutable shapes;
    address public immutable packs;

    event PulledWithPrizes(
        address indexed player, uint256 count, uint256 shapeCount, uint256 packCount, uint256 prizeWei, uint256 ethIn, uint256 change
    );
    event CashedOut(address indexed player, address indexed recipient, uint256 shapeCount, uint256 packCount, uint256 amount);

    error NothingToRedeem();
    error InvalidRecipient();

    constructor(address engine_, address shapes_, address packs_) {
        engine = IDrawEngineBuy(engine_);
        shapes = shapes_;
        packs = packs_;
    }

    /// @notice Redeems the caller's `shapeIds` and `packIds` at face, then buys `count` pulls for the
    ///         caller with that ETH plus `msg.value`. The engine's own price, slippage, inventory and
    ///         deadline checks apply unchanged; unspent ETH returns to the caller.
    function pullWithPrizes(
        uint256[] calldata shapeIds,
        uint256[] calldata packIds,
        address referrer,
        uint256 count,
        uint256 maxAcquisitionFee,
        uint256 maxNegativeSlippageBps,
        uint256 expectedInventoryVersion,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory requestIds) {
        uint256 start = address(this).balance - msg.value;
        uint256 prizeWei = _redeem(shapeIds, packIds);
        requestIds = engine.acquireBatch{value: address(this).balance - start}(
            msg.sender, referrer, count, maxAcquisitionFee, 0, maxNegativeSlippageBps, expectedInventoryVersion, deadline
        );
        uint256 change = address(this).balance - start;
        if (change != 0) SafeTransferLib.forceSafeTransferETH(msg.sender, change);
        emit PulledWithPrizes(msg.sender, count, shapeIds.length, packIds.length, prizeWei, msg.value, change);
    }

    /// @notice Redeems the caller's `shapeIds` and `packIds` at face and sends the ETH to `recipient`.
    function cashOut(uint256[] calldata shapeIds, uint256[] calldata packIds, address recipient)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        amount = _redeem(shapeIds, packIds);
        if (amount == 0) revert NothingToRedeem();
        SafeTransferLib.forceSafeTransferETH(recipient, amount);
        emit CashedOut(msg.sender, recipient, shapeIds.length, packIds.length, amount);
    }

    /// @dev Takes each prize from the caller and redeems it as owner; returns the ETH received.
    function _redeem(uint256[] calldata shapeIds, uint256[] calldata packIds) internal returns (uint256 received) {
        uint256 before = address(this).balance;
        uint256 n = shapeIds.length;
        if (n != 0) {
            for (uint256 i; i < n; ++i) {
                IPrizeCollection(shapes).transferFrom(msg.sender, address(this), shapeIds[i]);
            }
            IShapesRedeem(shapes).redeemBatch(shapeIds);
        }
        for (uint256 i; i < packIds.length; ++i) {
            IPrizeCollection(packs).transferFrom(msg.sender, address(this), packIds[i]);
            IPacksRedeem(packs).redeem(packIds[i]);
        }
        received = address(this).balance - before;
    }

    /// @dev Redemption payouts and the engine's change arrive here within a call.
    receive() external payable {}
}
