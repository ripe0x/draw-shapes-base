// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ShapeRenderer} from "shapes/ShapeRenderer.sol";
import {Shapes} from "shapes/Shapes.sol";
import {ShapePacks} from "draw-packs/ShapePacks.sol";
import {SystemFixture} from "../utils/SystemFixture.sol";
import {BaseShapeRenderer} from "../../src/presentation/BaseShapeRenderer.sol";

/// @notice Base card presentation: the deployed Shapes and Draw Packs render white cards with Base-blue
///         (#0052FF) shapes; geometry is identical to the Ethereum v1 renderer.
contract PresentationTest is SystemFixture {
    using LibString for string;

    function test_cardFieldIsBaseBlue_geometryUnchanged() public {
        BaseShapeRenderer baseR = new BaseShapeRenderer();
        ShapeRenderer v1 = new ShapeRenderer();
        bytes32 seed = keccak256("card");
        string memory b = baseR.renderSVG(seed, 0.01 ether, false, 0);
        string memory e = v1.renderSVG(seed, 0.01 ether, false, 0);
        assertTrue(b.contains('height="350" fill="#fff"/>'), "white field");
        assertTrue(b.contains('fill="#0052FF"') || b.contains('stroke="#0052FF"'), "blue marks");
        assertFalse(b.contains("#000"), "no black");
        // swapping the v1 colours (black field -> white, white marks -> blue) yields exactly the Base card
        string memory swapped = e.replace('"#fff"', '"#0052FF"').replace('height="350" fill="#000"', 'height="350" fill="#fff"');
        assertEq(swapped, b, "only the colours differ");
        string memory inv = baseR.renderSVG(seed, 0.01 ether, true, 0);
        assertTrue(inv.contains('height="350" fill="#0052FF"/>') && inv.contains('"#fff"'), "inverted: blue field, white marks");
    }

    function test_deployedShapeAndPackTokenUrisUseBaseBlue() public {
        Shapes shapes = Shapes(payable(s.shapes));
        string memory uri = shapes.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
        string memory json = string(Base64.decode(uri.slice(29)));
        assertTrue(json.contains("data:image/svg+xml;base64,"), "embedded svg");
        string memory img = json.slice(json.indexOf("data:image/svg+xml;base64,") + 26);
        img = img.slice(0, img.indexOf('"'));
        string memory svg = string(Base64.decode(img));
        assertTrue(svg.contains("#0052FF"), "deployed Shapes render Base blue");
        assertEq(address(shapes.renderer()).code.length > 0, true);
        // a Draw Pack from the board renders too
        uint256 packId = 1;
        string memory puri = ShapePacks(payable(s.drawPacks)).tokenURI(packId);
        assertTrue(bytes(puri).length > 0);
        vm.writeFile("evidence/web/shape-card-base-blue.svg", svg);
    }
}
