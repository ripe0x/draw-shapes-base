// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SystemFixture} from "../utils/SystemFixture.sol";
import {LibString} from "solady/utils/LibString.sol";

interface ICollectionCopy {
    function tokenNamePrefix() external view returns (string memory);
    function description() external view returns (string memory);
}

interface IShapesView {
    function collection() external view returns (address);
    function name() external view returns (string memory);
}

/// @notice The production deployment's Base identity: Shapes on Base carry their own metadata copy
///         (a separate collection from Shapes on Ethereum) and the packs collection is named for Base.
contract DeploymentTest is SystemFixture {
    function test_baseCollectionIdentity() public view {
        ICollectionCopy c = ICollectionCopy(IShapesView(s.shapes).collection());
        assertEq(c.tokenNamePrefix(), "Base Shape ");
        assertTrue(LibString.contains(c.description(), "separate collection from Shapes on Ethereum"));
        assertEq(IShapesView(s.shapes).name(), "Shapes", "token contract unchanged (ERC-721 name)");
        assertEq(IShapesView(s.drawPacks).name(), "Base Draw Packs");
    }
}
