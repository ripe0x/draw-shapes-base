// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Compiles the canonical v4 PoolManager (pinned v4-core) so tests can `deployCode` it. Base mainnet
// uses the canonical deployment at 0x498581fF718922c3f8e6A244956aF099B2652b2b.
import {PoolManager} from "v4-core/PoolManager.sol";
