// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFV2PlusClient} from "../../src/vendor/chainlink/VRFV2PlusClient.sol";

interface IRawFulfill {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

/// @notice Minimal Chainlink VRF v2.5 coordinator double: stores requests, bills a flat native
///         amount per fulfilment from the subscription and calls back with the requested gas limit.
contract MockVRFCoordinator {
    struct Request {
        address consumer;
        uint256 subId;
        uint32 callbackGasLimit;
        uint16 confirmations;
        uint256 blockNumber;
        bool done;
    }

    uint256 public nextRequestId = 1;
    uint256 public nextSubId = 1;
    /// @dev Chainlink v2.5 native billing: (callback gas + verification and accounting overhead) x the
    ///      oracle's gas price x (1 + 60 % premium) + L1 data fee. Defaults from live Base fulfilments.
    uint256 public billGasPrice = 0.00615 gwei;
    uint256 public billOverheadGas = 300_000 + 42_500;
    uint256 public billL1Wei = 0.0000005 ether;
    uint256 public totalBilled;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => uint96) public nativeBalance;
    mapping(uint256 => address) public subOwner;
    mapping(uint256 => uint256) public outstanding;
    uint256[] public openRequests;

    event Requested(uint256 indexed requestId, address consumer, uint32 gasLimit);
    event Fulfilled(uint256 indexed requestId, bool success, uint256 gasUsed);

    function createSubscription() external returns (uint256 subId) {
        subId = nextSubId++;
        subOwner[subId] = msg.sender;
    }

    function addConsumer(uint256, address) external {}

    function fundSubscriptionWithNative(uint256 subId) external payable {
        nativeBalance[subId] += uint96(msg.value);
    }

    function getSubscription(uint256 subId)
        external
        view
        returns (uint96 balance, uint96 nativeBal, uint64 reqCount, address owner, address[] memory consumers)
    {
        return (0, nativeBalance[subId], 0, subOwner[subId], consumers);
    }

    function pendingRequestExists(uint256 subId) external view returns (bool) {
        return outstanding[subId] != 0;
    }

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 id) {
        id = nextRequestId++;
        requests[id] = Request(msg.sender, req.subId, req.callbackGasLimit, req.requestConfirmations, block.number, false);
        outstanding[req.subId] += 1;
        openRequests.push(id);
        emit Requested(id, msg.sender, req.callbackGasLimit);
    }

    function openCount() external view returns (uint256) {
        return openRequests.length;
    }

    /// @notice Fulfils `id` with `word`, as the real coordinator would, with the stored gas limit.
    function fulfill(uint256 id, uint256 word) public returns (bool success) {
        Request storage r = requests[id];
        require(!r.done && r.consumer != address(0), "bad request");
        require(block.number >= r.blockNumber + r.confirmations, "too early");
        r.done = true;
        outstanding[r.subId] -= 1;
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        uint256 g = gasleft();
        (success,) = r.consumer.call{gas: r.callbackGasLimit}(abi.encodeCall(IRawFulfill.rawFulfillRandomWords, (id, words)));
        uint256 used = g - gasleft();
        uint96 bill = uint96((used + billOverheadGas) * billGasPrice * 160 / 100 + billL1Wei);
        require(nativeBalance[r.subId] >= bill, "subscription underfunded");
        nativeBalance[r.subId] -= bill;
        totalBilled += bill;
        emit Fulfilled(id, success, used);
    }

    function setBilling(uint256 gasPrice, uint256 overheadGas, uint256 l1Wei) external {
        (billGasPrice, billOverheadGas, billL1Wei) = (gasPrice, overheadGas, l1Wei);
    }

    /// @notice Marks `id` consumed without a callback (a lost callback).
    function drop(uint256 id) external {
        Request storage r = requests[id];
        require(!r.done, "done");
        r.done = true;
        outstanding[r.subId] -= 1;
    }
}
