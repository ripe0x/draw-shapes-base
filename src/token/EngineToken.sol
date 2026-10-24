// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @title EngineToken (ENGINE)
/// @notice Ordinary transferable ERC-20 of Draw Shapes. The whole supply is minted once at
///         construction to the given recipients (the opening market liquidity and the genesis farm).
///         There is no owner, no mint function, no transfer restriction and no upgrade path. Holders
///         may burn their own tokens; the buyback and the farm's retirement of unearned rewards use it.
/// @dev ENGINE is a speculative token. It is not a claim on any ETH held by the game, its prizes or
///      its treasury.
contract EngineToken is ERC20 {
    error LengthMismatch();
    error ZeroAmount();

    constructor(address[] memory recipients, uint256[] memory amounts) {
        if (recipients.length != amounts.length || recipients.length == 0) revert LengthMismatch();
        for (uint256 i; i < recipients.length; ++i) {
            if (amounts[i] == 0) revert ZeroAmount();
            _mint(recipients[i], amounts[i]);
        }
    }

    function name() public pure override returns (string memory) {
        return "Draw Shapes Engine";
    }

    function symbol() public pure override returns (string memory) {
        return "ENGINE";
    }

    /// @notice Burns `amount` of the caller's tokens, reducing total supply.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
