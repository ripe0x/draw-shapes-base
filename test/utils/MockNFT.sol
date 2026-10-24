// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "solady/tokens/ERC721.sol";

/// @notice ERC-721 with a switch that makes transfers to chosen recipients revert, used to force
///         failed prize deliveries.
contract MockNFT is ERC721 {
    mapping(address => bool) public blocked;
    uint256 public nextId = 1;

    function name() public pure override returns (string memory) {
        return "Mock";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function mint(address to) external returns (uint256 id) {
        id = nextId++;
        _mint(to, id);
    }

    function setBlocked(address who, bool value) external {
        blocked[who] = value;
    }

    function _beforeTokenTransfer(address, address to, uint256) internal view override {
        require(!blocked[to], "blocked");
    }
}
