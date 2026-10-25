// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Derived from FWAClone (Token Works FWA V2 standard custom pool, MIT), verified source of
// 0xeaa4d032908a9734a2c7939c0d211c35ad51eb31 on Ethereum mainnet, vendored by ripe0x/draw-shapes at
// external/fwa-v2/mainnet/FWAClone. The listing, staging, reservation, segment tree, ordered
// processing, slippage, delivery-escrow and refund code is retained. The differences are listed in
// docs/ENGINE.md and summarised in the contract notice below.

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IVRFCoordinatorV2Plus} from "../vendor/chainlink/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "../vendor/chainlink/VRFV2PlusClient.sol";

interface IERC721Minimal {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IPurchaseOperator {
    function canPurchase(address purchaser) external view returns (bool);
}

/// @title DrawEngine
/// @notice The Draw Shapes on Base gacha engine: a single, protocol-owned fork of FWA's custom pool.
///         Approved suppliers escrow ERC-721 prizes at a notional price. A listing's selection weight
///         is `1e36 / price`, so the acquisition fee, the expected value `Σ(wᵢ·pᵢ) / Σwᵢ`, is the
///         harmonic mean of the active notionals. Each paid acquisition draws one listing with a
///         Chainlink VRF v2.5 word and delivers its NFT to the purchaser.
/// @dev Changes from FWAClone:
///      - No factory: VRF, limits and policy are local and set by `governance` within hard bounds.
///      - No FWA edge: `acquisitionFee()` is the harmonic mean itself. The full fee accrues to the
///        captured listing's depositor.
///      - A settlement fee of `settlementFeeBps` (launch 100) of the acquisition fee is paid on top
///        and escrowed with it. A fulfilled acquisition splits it between its referrer, Token Works
///        and development by the fee policy snapshotted at request; every refund path returns it.
///      - One VRF request per `acquireBatch` call. Acquisition `i` of a batch uses
///        `keccak256(abi.encode(word, i))`, so every acquisition keeps an independent outcome while
///        the batch shares one callback and one deadline.
///      - Acquisition ids are their local sequence numbers.
///      - A participation ledger counts, per 24-hour ledger day of acceptance, the acquisitions
///        accepted and resolved and, per purchaser, fulfilled acquisitions (units) and a VRF-derived
///        bonus weight. The genesis farm reads it.
///      - Multiple suppliers (governance-approved); proceeds accrue per depositor; a depositor may
///        hand listings to another supplier without moving the NFT (controller replacement).
///      - `guardian` may pause new acquisitions. Pausing never blocks processing, delivery, refunds
///        or withdrawals.
///      - After the delivery window anyone may convert a stuck delivery to the purchaser's refund
///        credit, so a ledger day always resolves.
contract DrawEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    enum ListingStatus {
        None,
        Active,
        Allocated,
        Withdrawn,
        Settled,
        Staged,
        DeliveryPending,
        DeliveryRefunded
    }

    enum AcquisitionStatus {
        None,
        Pending,
        Fulfilled,
        Expired,
        Refunded,
        Ready,
        TimedOut,
        DeliveryPending,
        DeliveryRefunded
    }

    struct ListingInput {
        address collection;
        uint256 tokenId;
        uint256 price;
    }

    struct Listing {
        address collection;
        address depositor;
        address purchaser;
        uint256 tokenId;
        uint256 weight;
        uint256 price;
        uint256 slot;
        ListingStatus status;
    }

    struct Acquisition {
        address purchaser;
        uint256 requestBlock;
        uint256 priceEscrowed;
        uint256 listingId;
        AcquisitionStatus status;
    }

    struct AcquisitionMeta {
        uint64 sequence;
        uint64 wordDeadlineBlock;
        uint64 ledgerDay;
        uint16 maxPositiveSlippageBps;
        uint16 maxNegativeSlippageBps;
        uint256 randomWord;
    }

    /// @notice Settlement fee escrowed with an acquisition and the referrer and policy it settles under.
    struct SettlementTerms {
        address referrer;
        uint96 amount;
        uint32 policyId;
    }

    /// @notice Shares of the settlement fee, in bps of the fee. `devBps` is the remainder.
    struct FeePolicy {
        uint16 referrerBps;
        uint16 tokenWorksBps;
    }

    struct PendingDelivery {
        uint256 requestId;
        uint64 deadline;
    }

    struct VrfBatch {
        uint64 firstSequence;
        uint32 count;
        bool observed;
    }

    struct DayTotals {
        uint64 accepted;
        uint64 resolved;
        uint64 units;
        uint64 bonusWeight;
    }

    struct UserDay {
        uint64 units;
        uint64 bonusWeight;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TREE_DEPTH = 32;
    uint256 internal constant CAPACITY = 1 << TREE_DEPTH;
    uint256 internal constant LEAF_BASE = CAPACITY;

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_INVENTORY_BATCH = 20;
    uint256 internal constant INVERSE_WEIGHT_NUMERATOR = 1e36;
    uint256 internal constant NFT_DELIVERY_GAS = 150_000;
    uint256 internal constant PURCHASE_OPERATOR_GAS = 100_000;
    uint256 public constant DELIVERY_WINDOW = 7 days;

    /// @notice Pass as `expectedInventoryVersion` to accept any inventory version. The fee and
    ///         weighted-value guards still apply.
    uint256 public constant ANY_INVENTORY_VERSION = type(uint256).max;

    /// @notice Hard ceilings governance cannot exceed.
    uint256 public constant MAX_SETTLEMENT_FEE_BPS = 200;
    uint256 public constant MAX_INVENTORY_COOLDOWN = 1 hours;
    uint256 public constant MAX_VRF_FEE_PER_BATCH = 0.002 ether;
    /// @notice Ceiling on the VRF fluctuation buffer and on the Chainlink premium assumption.
    uint256 public constant MAX_VRF_BUFFER_BPS = 5_000;
    uint256 public constant MAX_VRF_PREMIUM_BPS = 20_000;
    uint256 public constant MAX_ACQUISITIONS_PER_TX_CAP = 50;
    uint256 public constant MAX_UNSETTLED_CAP = 1_000;

    uint32 internal constant NUM_WORDS = 1;
    uint32 public constant MIN_CALLBACK_GAS_LIMIT = 150_000;
    uint32 public constant MAX_CALLBACK_GAS_LIMIT = 2_500_000;
    /// @dev The callback attempts an isolated single-acquisition self-call only with at least this much
    ///      gas, and gives it everything above the return reserve (a cold first acquisition needs
    ///      ~620k; a fixed stipend below that blocked the head until a keeper processed it).
    uint256 internal constant CALLBACK_FAST_PATH_GAS = 400_000;
    uint256 internal constant CALLBACK_RETURN_GAS_RESERVE = 60_000;
    uint256 internal constant MIN_REQUEST_CONFIRMATIONS = 3;
    uint256 internal constant MAX_REQUEST_CONFIRMATIONS = 200;
    uint256 internal constant MIN_CALLBACK_SLACK_BLOCKS = 2;
    uint256 internal constant MAX_WINDOW_BLOCKS = 7_200;
    uint256 internal constant MAX_ACTIVATIONS_PER_ACQUISITION = 16;

    /// @notice Ledger day length.
    uint256 public constant LEDGER_DAY = 1 days;

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Slow policy authority (a timelock). Sets bounded parameters, suppliers and recipients.
    address public governance;
    address public pendingGovernance;
    /// @notice Fast emergency authority. May pause and unpause new acquisitions only.
    address public guardian;
    mapping(address supplier => bool) public isSupplier;

    /*//////////////////////////////////////////////////////////////
                              VRF CONFIG
    //////////////////////////////////////////////////////////////*/

    IVRFCoordinatorV2Plus public vrfCoordinator;
    uint256 public vrfSubscriptionId;
    bytes32 public vrfKeyHash;
    uint16 public requestConfirmations;
    /// @notice Callback gas of a batch: `callbackGasBase + count * callbackGasPerAcquisition`, capped.
    uint32 public callbackGasBase;
    uint32 public callbackGasPerAcquisition;
    /// @notice Purchaser-funded VRF charge of a batch (FWA V2 `FWACloneVRFService.requestFee`,
    ///         per batch instead of per request): `(overheadGas + callbackGasLimit(count)) *
    ///         max(block.basefee, minGasPrice) * (10_000 + premiumBps + bufferBps) / 10_000 + flatWei`,
    ///         capped at `MAX_VRF_FEE_PER_BATCH`. `overheadGas` covers proof verification and
    ///         Chainlink's post-callback accounting; the callback is charged at its requested limit
    ///         (Chainlink bills only the gas used); `premiumBps` is Chainlink's native premium;
    ///         `bufferBps` absorbs gas-price movement until fulfilment; `flatWei` covers the L1 data
    ///         fee. The whole charge is forwarded to the subscription in the purchase transaction.
    struct VrfFeeConfig {
        uint32 overheadGas;
        uint64 minGasPrice;
        uint16 premiumBps;
        uint16 bufferBps;
        uint96 flatWei;
    }

    VrfFeeConfig public vrfFeeConfig;
    /// @notice Every VRF charge forwarded to the subscription, for reconciliation with Chainlink's bills.
    uint256 public vrfFeesCollected;

    /*//////////////////////////////////////////////////////////////
                         ACQUISITION SEQUENCER
    //////////////////////////////////////////////////////////////*/

    uint256 public maxActivationsPerAcquisition;
    uint256 public pendingAcquisitionCount;
    uint256 public unfulfilledVrfCount;
    uint256 public unsettledAcquisitionCount;
    uint256 public selectionTimeoutBlocks;
    uint256 public maxAcquisitionsPerTx;
    uint256 public maxUnsettledAcquisitions;
    uint64 public lastIssuedSequence;
    uint64 public nextSequenceToProcess = 1;

    /// @notice Set once by `activate`. Acquisitions are impossible before it.
    bool public activated;
    bool public paused;
    bool public retired;
    address public purchaseOperator;

    /*//////////////////////////////////////////////////////////////
                            ECONOMIC CONFIG
    //////////////////////////////////////////////////////////////*/

    uint256 public selectionSlippageBps;
    uint256 public inventoryVersion;
    uint64 public lastInventoryChangeAt;
    uint256 public inventoryChangeCooldown;

    uint256 public settlementFeeBps;
    FeePolicy[] internal _feePolicies;
    address public tokenWorksRecipient;
    address public devRecipient;

    /*//////////////////////////////////////////////////////////////
                            LISTING STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public nextListingId = 1;
    mapping(uint256 listingId => Listing) public listings;
    mapping(uint256 listingId => PendingDelivery delivery) public pendingDeliveries;
    uint256 public deliveryEscrowTotal;
    mapping(address collection => mapping(uint256 tokenId => uint256 listingId)) internal liveNFTListing;

    uint256 internal stagingHead;
    uint256 internal stagingTail;
    mapping(uint256 listingId => uint256) internal stagingNext;
    mapping(uint256 listingId => uint256) internal stagingPrev;
    uint256 public stagedCount;
    mapping(uint256 listingId => uint64 sequence) public reservedForSequence;
    uint256 public reservedStagedCount;
    mapping(uint64 sequence => uint256[]) internal reservedListingsBySequence;

    mapping(uint256 slot => uint256 listingId) public slotToListing;
    uint256 public activeListingCount;
    uint256 public totalWeight;
    /// @notice Σ(weightᵢ · priceᵢ) over active listings (FWA's historical name).
    uint256 public weightedBackingTotal;

    mapping(address depositor => uint256) public proceedsOf;
    uint256 public proceedsTotal;
    mapping(address recipient => uint256) public feeCreditOf;
    uint256 public feeCreditTotal;

    mapping(uint256 node => uint256 weight) internal tree;
    uint256 internal nextUnusedSlot = 1;
    uint256 internal freeSlotHead;
    mapping(uint256 slot => uint256 nextFreeSlot) internal nextFreeSlot;

    /*//////////////////////////////////////////////////////////////
                              ACQUISITION STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Keyed by acquisition id, which equals the acquisition's sequence.
    mapping(uint256 requestId => Acquisition) public acquisitions;
    mapping(uint256 requestId => AcquisitionMeta) public acquisitionMeta;
    mapping(uint256 requestId => SettlementTerms) public settlementTerms;
    mapping(uint256 requestId => uint256 vrfRequestId) public vrfRequestOf;
    mapping(uint256 vrfRequestId => VrfBatch) public vrfBatches;

    mapping(address purchaser => uint256 amount) public acquisitionRefundCredit;
    uint256 public acquisitionRefundCreditTotal;
    /// @notice Acquisition fees plus settlement fees of unsettled acquisitions.
    uint256 public acquisitionEscrowTotal;

    /*//////////////////////////////////////////////////////////////
                          PARTICIPATION LEDGER
    //////////////////////////////////////////////////////////////*/

    uint64 public ledgerOrigin;
    mapping(uint256 day => DayTotals) public dayTotals;
    mapping(uint256 day => mapping(address purchaser => UserDay)) public userDay;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event NFTListed(
        uint256 indexed listingId,
        uint256 indexed slot,
        address indexed depositor,
        address collection,
        uint256 tokenId,
        uint256 weight,
        uint256 price
    );
    event ListingWithdrawn(uint256 indexed listingId, address indexed depositor, uint256 price);
    event ListingStaged(
        uint256 indexed listingId,
        address indexed depositor,
        address collection,
        uint256 tokenId,
        uint256 price,
        uint256 stagedAtBlock
    );
    event ListingTransferred(uint256 indexed listingId, address indexed from, address indexed to);
    event PriceUpdated(
        uint256 indexed listingId, address indexed depositor, uint256 oldPrice, uint256 newPrice, uint256 newWeight
    );
    event InventoryChanged(uint256 indexed version, uint64 changedAt);
    event AcquisitionRequested(
        uint256 indexed requestId,
        address indexed purchaser,
        uint256 acquisitionFee,
        uint256 settlementFee,
        address indexed referrer,
        address payer,
        uint256 totalWeight
    );
    event AcquisitionSequenced(
        uint256 indexed requestId, uint64 indexed sequence, uint64 wordDeadlineBlock, uint256 reservedCount
    );
    event RandomnessRequested(uint256 indexed vrfRequestId, uint64 firstSequence, uint256 count, uint32 gasLimit);
    event RandomnessCached(uint256 indexed requestId, uint64 indexed sequence, uint256 randomWord);
    event RandomnessTimedOut(
        uint256 indexed requestId, uint64 indexed sequence, uint64 wordDeadlineBlock, uint256 callbackBlock
    );
    event FulfillmentIgnored(uint256 indexed vrfRequestId);
    event UnfulfilledVrfReconciled(uint256 count);
    event AcquisitionProcessed(
        uint256 indexed requestId, uint64 indexed sequence, AcquisitionStatus status, address indexed processor
    );
    event AcquisitionRefundWithdrawn(address indexed purchaser, uint256 amount);
    event AcquisitionExpired(
        uint256 indexed requestId, uint64 indexed sequence, address indexed purchaser, uint256 refund
    );
    event AcquisitionRefundedNoListing(uint256 indexed requestId, address indexed purchaser, uint256 refund);
    event AcquisitionRefundedSlippage(
        uint256 indexed requestId, address indexed purchaser, uint256 refund, uint256 escrowedFee, uint256 liveFee
    );
    event NFTAllocated(
        uint256 indexed requestId,
        uint256 indexed listingId,
        address indexed purchaser,
        address depositor,
        uint256 price,
        uint256 randomWord
    );
    event NFTDeliveryFailed(uint256 indexed listingId, address indexed recipient, address collection, uint256 tokenId);
    event NFTDeliveryCompleted(uint256 indexed listingId, uint256 indexed requestId, address indexed purchaser);
    event NFTDeliveryRefunded(
        uint256 indexed listingId, uint256 indexed requestId, address indexed purchaser, uint256 amount
    );
    event RefundedNFTRecovered(uint256 indexed listingId, address indexed depositor);
    event ProceedsAccrued(uint256 indexed requestId, address indexed depositor, uint256 amount);
    event ProceedsWithdrawn(address indexed depositor, uint256 amount);
    event SettlementFeeSplit(
        uint256 indexed requestId, address indexed referrer, uint256 referrerAmount, uint256 tokenWorksAmount, uint256 devAmount
    );
    event FeeCreditWithdrawn(address indexed recipient, address indexed to, uint256 amount);
    event ParticipationRecorded(uint256 indexed day, address indexed purchaser, uint256 requestId, uint256 bonusWeight);
    event Activated(uint64 ledgerOrigin);
    event PausedSet(bool paused);
    event Retired();
    event SupplierSet(address indexed supplier, bool allowed);
    event GovernanceProposed(address indexed pending);
    event GovernanceTransferred(address indexed previous, address indexed next);
    event GuardianSet(address indexed guardian);
    event PurchaseOperatorSet(address indexed oldOperator, address indexed newOperator);
    event FeePolicySet(uint256 indexed policyId, uint256 settlementFeeBps, uint256 referrerBps, uint256 tokenWorksBps);
    event FeeRecipientsSet(address tokenWorks, address dev);
    event LimitsSet(uint256 maxPerTx, uint256 maxUnsettled, uint256 activations, uint256 slippageBps, uint256 cooldown);
    event VrfConfigSet(address coordinator, uint256 subId, bytes32 keyHash, uint16 confirmations, uint32 gasBase, uint32 gasPerAcquisition, uint256 timeoutBlocks);
    event VrfFeeConfigSet(VrfFeeConfig config);
    event VrfFeeCollected(uint64 indexed firstSequence, uint256 count, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroPrice();
    error PriceTooHigh();
    error InvalidCollection();
    error ListingNotActive();
    error NotDepositor();
    error NoActiveListings();
    error WithdrawLocked();
    error InvalidTreeResult();
    error ActiveListingCapacityReached();
    error NFTTransferFailed();
    error InsufficientPayment();
    error AcquisitionFeeTooHigh();
    error InvalidAcquisitionCount();
    error InvalidInventoryBatch();
    error PoolValueTooLow();
    error InvalidConfig();
    error NoProceeds();
    error DeliveryNotPending();
    error DeliveryNotRefunded();
    error DeliveryWindowNotElapsed();
    error DeliveryWindowElapsed();
    error OnlySelf();
    error NFTAlreadyControlled();
    error StaleNFTController();
    error NotActivated();
    error AlreadyActivated();
    error OnlyCoordinator();
    error SequenceInvariantBroken();
    error NoAcquisitionRefund();
    error AcquisitionStateLocked();
    error VrfRequestsPending();
    error DuplicateRequestId();
    error NotSupplier();
    error NotGovernance();
    error NotGuardian();
    error Paused();
    error InventoryVersionMismatch(uint256 expected, uint256 actual);
    error InventoryChangeCooldownActive(uint256 purchasesResumeAt);
    error TransactionExpired(uint256 deadline);
    error PoolAlreadyRetired();
    error InvalidPurchaseOperator();
    error PurchaseNotAllowed();
    error PurchaseOperatorCheckFailed();
    error TooManyUnsettled();
    error NoFeeCredit();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    struct VrfConfig {
        address coordinator;
        uint256 subscriptionId;
        bytes32 keyHash;
        uint16 requestConfirmations;
        uint32 callbackGasBase;
        uint32 callbackGasPerAcquisition;
        uint256 selectionTimeoutBlocks;
    }

    struct Limits {
        uint256 maxAcquisitionsPerTx;
        uint256 maxUnsettledAcquisitions;
        uint256 maxActivationsPerAcquisition;
        uint256 selectionSlippageBps;
        uint256 inventoryChangeCooldown;
    }

    struct Fees {
        uint256 settlementFeeBps;
        uint16 referrerBps;
        uint16 tokenWorksBps;
        address tokenWorksRecipient;
        address devRecipient;
    }

    constructor(
        address governance_,
        address guardian_,
        VrfConfig memory vrf,
        VrfFeeConfig memory vrfFee,
        Limits memory limits,
        Fees memory fees
    ) {
        if (governance_ == address(0) || guardian_ == address(0)) revert InvalidConfig();
        governance = governance_;
        guardian = guardian_;
        emit GovernanceTransferred(address(0), governance_);
        emit GuardianSet(guardian_);
        _setVrfConfig(vrf);
        _setVrfFeeConfig(vrfFee);
        _setLimits(limits);
        _setFeePolicy(fees.settlementFeeBps, fees.referrerBps, fees.tokenWorksBps);
        _setFeeRecipients(fees.tokenWorksRecipient, fees.devRecipient);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT AN ERC721
    //////////////////////////////////////////////////////////////*/

    /// @notice Escrow an ERC721 at a notional price. The supplier must approve this contract first.
    function listNFT(address collection, uint256 tokenId, uint256 price)
        external
        nonReentrant
        returns (uint256 listingId)
    {
        _requireInventoryInputAllowed();
        listingId = _listNFT(collection, tokenId, price);
        _recordInventoryChange();
    }

    /// @notice Atomically escrow up to `MAX_INVENTORY_BATCH` NFTs and publish one inventory version.
    function listNFTs(ListingInput[] calldata items) external nonReentrant returns (uint256[] memory listingIds) {
        _requireInventoryInputAllowed();
        uint256 length = items.length;
        _validateInventoryBatch(length);
        listingIds = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            ListingInput calldata item = items[i];
            listingIds[i] = _listNFT(item.collection, item.tokenId, item.price);
        }
        _recordInventoryChange();
    }

    function _requireInventoryInputAllowed() internal view {
        if (!isSupplier[msg.sender]) revert NotSupplier();
        if (retired) revert PoolAlreadyRetired();
    }

    function _validateInventoryBatch(uint256 length) internal pure {
        if (length == 0 || length > MAX_INVENTORY_BATCH) revert InvalidInventoryBatch();
    }

    function _listNFT(address collection, uint256 tokenId, uint256 price) internal returns (uint256 listingId) {
        if (price == 0) revert ZeroPrice();
        if (collection.code.length == 0) revert InvalidCollection();
        if (liveNFTListing[collection][tokenId] != 0) revert NFTAlreadyControlled();

        uint256 weight = INVERSE_WEIGHT_NUMERATOR / price;
        if (weight == 0) revert PriceTooHigh();

        IERC721Minimal(collection).transferFrom(msg.sender, address(this), tokenId);
        if (IERC721Minimal(collection).ownerOf(tokenId) != address(this)) revert NFTTransferFailed();

        listingId = nextListingId++;
        liveNFTListing[collection][tokenId] = listingId;

        listings[listingId] = Listing({
            collection: collection,
            depositor: msg.sender,
            purchaser: address(0),
            tokenId: tokenId,
            weight: weight,
            price: price,
            slot: 0,
            status: ListingStatus.Active
        });
        if (unsettledAcquisitionCount == 0 && stagingHead == 0) {
            _activateListing(listingId);
        } else {
            listings[listingId].status = ListingStatus.Staged;
            _stagingPush(listingId);
            emit ListingStaged(listingId, msg.sender, collection, tokenId, price, block.number);
            if (unsettledAcquisitionCount == 0) _drainStaging(maxActivationsPerAcquisition);
        }
    }

    /// @notice Earliest timestamp at which a new purchase may execute.
    function purchasesResumeAt() public view returns (uint256) {
        return uint256(lastInventoryChangeAt) + inventoryChangeCooldown;
    }

    function _recordInventoryChange() internal {
        uint256 version = inventoryVersion + 1;
        inventoryVersion = version;
        uint64 changedAt = uint64(block.timestamp);
        lastInventoryChangeAt = changedAt;
        emit InventoryChanged(version, changedAt);
    }

    /*//////////////////////////////////////////////////////////////
                          STAGING QUEUE
    //////////////////////////////////////////////////////////////*/

    /// @notice Permissionlessly activate up to `maxCount` unreserved FIFO listings while no acquisition
    ///         remains unresolved.
    function activateListings(uint256 maxCount) external nonReentrant {
        if (unsettledAcquisitionCount != 0) return;
        _drainStaging(maxCount);
    }

    function _activateListing(uint256 listingId) internal {
        Listing storage listing = listings[listingId];
        uint256 price = listing.price;
        uint256 weight = listing.weight;
        uint256 slot = _allocateSlot();
        listing.slot = slot;
        slotToListing[slot] = listingId;
        _addTreeWeight(slot, weight);
        totalWeight += weight;
        weightedBackingTotal += weight * price;
        activeListingCount++;
        listing.status = ListingStatus.Active;
        emit NFTListed(listingId, slot, listing.depositor, listing.collection, listing.tokenId, weight, price);
    }

    function _drainStaging(uint256 maxCount) internal {
        uint256 drained = 0;
        while (drained < maxCount) {
            uint256 head = stagingHead;
            if (head == 0) return;
            _stagingUnlink(head);
            _activateListing(head);
            unchecked {
                drained++;
            }
        }
    }

    function _reserveStagedBatch(uint64 sequence) internal returns (uint256 count) {
        uint256 maxCount = maxActivationsPerAcquisition;
        while (count < maxCount) {
            uint256 head = stagingHead;
            if (head == 0) break;
            _stagingUnlink(head);
            reservedForSequence[head] = sequence;
            reservedListingsBySequence[sequence].push(head);
            unchecked {
                ++reservedStagedCount;
                ++count;
            }
        }
    }

    function _activateReservedBatch(uint64 sequence) internal {
        uint256[] storage batch = reservedListingsBySequence[sequence];
        uint256 length = batch.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 listingId = batch[i];
            if (reservedForSequence[listingId] != sequence || listings[listingId].status != ListingStatus.Staged) {
                revert SequenceInvariantBroken();
            }
            delete reservedForSequence[listingId];
            unchecked {
                --reservedStagedCount;
            }
            _activateListing(listingId);
        }
        delete reservedListingsBySequence[sequence];
    }

    function reservedListingCount(uint64 sequence) external view returns (uint256) {
        return reservedListingsBySequence[sequence].length;
    }

    function reservedListingAt(uint64 sequence, uint256 index) external view returns (uint256) {
        return reservedListingsBySequence[sequence][index];
    }

    function _stagingPush(uint256 listingId) internal {
        uint256 tail = stagingTail;
        stagingPrev[listingId] = tail;
        stagingNext[listingId] = 0;
        if (tail == 0) {
            stagingHead = listingId;
        } else {
            stagingNext[tail] = listingId;
        }
        stagingTail = listingId;
        unchecked {
            ++stagedCount;
        }
    }

    function _stagingUnlink(uint256 listingId) internal {
        uint256 prev = stagingPrev[listingId];
        uint256 next = stagingNext[listingId];
        if (prev == 0) {
            stagingHead = next;
        } else {
            stagingNext[prev] = next;
        }
        if (next == 0) {
            stagingTail = prev;
        } else {
            stagingPrev[next] = prev;
        }
        delete stagingPrev[listingId];
        delete stagingNext[listingId];
        unchecked {
            --stagedCount;
        }
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAW / HAND OFF
    //////////////////////////////////////////////////////////////*/

    function _requireExitUnlocked() internal view {
        if (unsettledAcquisitionCount != 0) revert WithdrawLocked();
    }

    function _activeOwned(uint256 listingId) internal view returns (Listing storage listing) {
        listing = listings[listingId];
        if (listing.status != ListingStatus.Active) revert ListingNotActive();
        if (listing.depositor != msg.sender) revert NotDepositor();
    }

    /// @notice Withdraw active or unreserved staged inventory to a receiver chosen by its depositor.
    function withdrawListingTo(uint256 listingId, address recipient) external nonReentrant {
        _validateInventoryRecipient(recipient);
        _withdrawListing(listingId, recipient);
        _recordInventoryChange();
    }

    /// @notice Atomically withdraw up to `MAX_INVENTORY_BATCH` listings and publish one inventory version.
    function withdrawListingsTo(uint256[] calldata listingIds, address recipient) external nonReentrant {
        _validateInventoryRecipient(recipient);
        uint256 length = listingIds.length;
        _validateInventoryBatch(length);
        for (uint256 i; i < length; ++i) {
            _withdrawListing(listingIds[i], recipient);
        }
        _recordInventoryChange();
    }

    function _validateInventoryRecipient(address recipient) internal view {
        if (recipient == address(0) || recipient == address(this)) revert InvalidConfig();
    }

    function _withdrawListing(uint256 listingId, address recipient) internal {
        Listing storage listing = listings[listingId];
        ListingStatus status = listing.status;
        if (status == ListingStatus.Active) {
            _requireExitUnlocked();
        } else if (status == ListingStatus.Staged) {
            if (reservedForSequence[listingId] != 0) revert WithdrawLocked();
        } else {
            revert ListingNotActive();
        }
        if (listing.depositor != msg.sender) revert NotDepositor();

        uint256 price = listing.price;
        address collection = listing.collection;
        uint256 tokenId = listing.tokenId;
        if (status == ListingStatus.Active) _settleAndRemove(listingId);
        else _stagingUnlink(listingId);
        listing.status = ListingStatus.Withdrawn;
        if (liveNFTListing[collection][tokenId] != listingId) revert StaleNFTController();
        delete liveNFTListing[collection][tokenId];

        IERC721Minimal(collection).safeTransferFrom(address(this), recipient, tokenId);
        emit ListingWithdrawn(listingId, msg.sender, price);
    }

    /// @notice Hand listings to another approved supplier without moving their NFTs or prices.
    ///         The new depositor receives the proceeds of later captures and controls the listing.
    /// @dev Active listings move only while no acquisition is unresolved, the same lock as a
    ///      withdrawal, so an issued request always settles to the depositor it saw. Unreserved
    ///      staged listings may move at any time.
    function transferListings(uint256[] calldata listingIds, address to) external nonReentrant {
        if (!isSupplier[to]) revert NotSupplier();
        uint256 length = listingIds.length;
        _validateInventoryBatch(length);
        for (uint256 i; i < length; ++i) {
            uint256 listingId = listingIds[i];
            Listing storage listing = listings[listingId];
            if (listing.depositor != msg.sender) revert NotDepositor();
            if (listing.status == ListingStatus.Active) {
                _requireExitUnlocked();
            } else if (listing.status == ListingStatus.Staged) {
                if (reservedForSequence[listingId] != 0) revert WithdrawLocked();
            } else if (listing.status != ListingStatus.DeliveryRefunded) {
                revert ListingNotActive();
            }
            listing.depositor = to;
            emit ListingTransferred(listingId, msg.sender, to);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           UPDATE LISTING PRICE
    //////////////////////////////////////////////////////////////*/

    /// @notice Change an active listing's notional price and inverse selection weight. Locked while
    ///         any acquisition is unresolved.
    function updatePrice(uint256 listingId, uint256 newPrice) external nonReentrant {
        if (retired) revert PoolAlreadyRetired();
        Listing storage listing = _activeOwned(listingId);
        if (newPrice == 0) revert ZeroPrice();
        uint256 oldPrice = listing.price;
        if (newPrice == oldPrice) revert InvalidConfig();
        _requireExitUnlocked();

        uint256 newWeight = INVERSE_WEIGHT_NUMERATOR / newPrice;
        if (newWeight == 0) revert PriceTooHigh();

        uint256 oldWeight = listing.weight;
        uint256 slot = listing.slot;
        if (newWeight > oldWeight) {
            _addTreeWeight(slot, newWeight - oldWeight);
        } else if (newWeight < oldWeight) {
            _removeTreeWeight(slot, oldWeight - newWeight);
        }
        totalWeight = totalWeight - oldWeight + newWeight;
        weightedBackingTotal = weightedBackingTotal - oldWeight * oldPrice + newWeight * newPrice;

        listing.price = newPrice;
        listing.weight = newWeight;
        _recordInventoryChange();

        emit PriceUpdated(listingId, msg.sender, oldPrice, newPrice, newWeight);
    }

    /*//////////////////////////////////////////////////////////////
                             PRICING
    //////////////////////////////////////////////////////////////*/

    /// @notice The acquisition fee: the harmonic mean of the active notionals, `Σ(wᵢ·pᵢ) / Σwᵢ`,
    ///         rounded down. Zero when nothing is listed.
    function acquisitionFee() public view returns (uint256) {
        if (totalWeight == 0) return 0;
        return weightedBackingTotal / totalWeight;
    }

    /// @notice Settlement fee charged on top of an acquisition fee of `fee`, rounded down.
    function settlementFeeFor(uint256 fee) public view returns (uint256) {
        return fee * settlementFeeBps / BPS;
    }

    /// @notice Quote a purchase of `count` acquisitions against its hypothetical idle FIFO activation.
    /// @return fee Acquisition fee per acquisition.
    /// @return settlementFee Settlement fee per acquisition.
    /// @return vrfFee VRF charge for the whole batch, shared by its acquisitions (see `vrfFeeFor`).
    /// @return total Full minimum payment, `count * (fee + settlementFee) + vrfFee`.
    function quoteAcquisitionPrice(uint256 count)
        public
        view
        returns (uint256 fee, uint256 settlementFee, uint256 vrfFee, uint256 total)
    {
        if (count == 0 || count > maxAcquisitionsPerTx) revert InvalidAcquisitionCount();
        uint256 weight = totalWeight;
        uint256 weightedValue = weightedBackingTotal;
        if (unsettledAcquisitionCount == 0) {
            uint256 remaining = count * maxActivationsPerAcquisition;
            uint256 listingId = stagingHead;
            while (listingId != 0 && remaining != 0) {
                Listing storage listing = listings[listingId];
                weight += listing.weight;
                weightedValue += listing.weight * listing.price;
                listingId = stagingNext[listingId];
                --remaining;
            }
        }
        if (weight != 0) fee = weightedValue / weight;
        settlementFee = settlementFeeFor(fee);
        vrfFee = vrfFeeFor(count);
        total = count * (fee + settlementFee) + vrfFee;
    }

    /// @notice Callback gas limit requested for a batch of `count` acquisitions.
    function callbackGasLimitFor(uint256 count) public view returns (uint256 gas) {
        gas = uint256(callbackGasBase) + count * callbackGasPerAcquisition;
        if (gas > MAX_CALLBACK_GAS_LIMIT) gas = MAX_CALLBACK_GAS_LIMIT;
    }

    /// @notice Purchaser VRF charge for one batch of `count` acquisitions at the current base fee.
    ///         Not refundable: Chainlink bills the request whether the acquisition later settles or not.
    function vrfFeeFor(uint256 count) public view returns (uint256 fee) {
        VrfFeeConfig memory c = vrfFeeConfig;
        uint256 price = block.basefee > c.minGasPrice ? block.basefee : c.minGasPrice;
        fee = (uint256(c.overheadGas) + callbackGasLimitFor(count)) * price * (BPS + c.premiumBps + c.bufferBps) / BPS
            + c.flatWei;
        if (fee > MAX_VRF_FEE_PER_BATCH) fee = MAX_VRF_FEE_PER_BATCH;
    }

    /*//////////////////////////////////////////////////////////////
                             REQUEST ACQUISITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pay for and request `count` acquisitions with one VRF request. Send at least
    ///         `quoteAcquisitionPrice(count).total`; any excess is refunded to the caller.
    /// @param purchaser Recipient of every acquisition, its NFT, participation units and refund rights.
    /// @param referrer Referrer credited with the referral share of each fulfilled acquisition's
    ///        settlement fee. Zero, the purchaser itself or this contract route that share to development.
    /// @param maxAcquisitionFee Revert if the live fee exceeds this. `0` disables the check.
    /// @param minWeightedValue Revert if `weightedBackingTotal` is below this. `0` disables the check.
    /// @param maxNegativeSlippageBps Tolerated fall of the live fee at ordered settlement.
    /// @param expectedInventoryVersion Exact inventory version, or `ANY_INVENTORY_VERSION`.
    /// @param deadline Last timestamp at which this transaction may execute.
    function acquireBatch(
        address purchaser,
        address referrer,
        uint256 count,
        uint256 maxAcquisitionFee,
        uint256 minWeightedValue,
        uint256 maxNegativeSlippageBps,
        uint256 expectedInventoryVersion,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory requestIds) {
        if (purchaser == address(0)) revert InvalidConfig();
        if (count == 0 || count > maxAcquisitionsPerTx) revert InvalidAcquisitionCount();
        if (maxNegativeSlippageBps > BPS) revert InvalidConfig();
        if (unsettledAcquisitionCount + count > maxUnsettledAcquisitions) revert TooManyUnsettled();
        _validateInventoryCommitment(expectedInventoryVersion, deadline);
        _validatePurchaseOperator(purchaser);

        if (unsettledAcquisitionCount == 0) _drainStaging(count * maxActivationsPerAcquisition);

        uint256 fee = _validateAcquisition(maxAcquisitionFee, minWeightedValue);
        uint256 settlementFee = settlementFeeFor(fee);
        uint256 vrfFee = vrfFeeFor(count);
        uint256 cost = count * (fee + settlementFee) + vrfFee;
        if (msg.value < cost) revert InsufficientPayment();

        if (referrer == purchaser || referrer == address(this)) referrer = address(0);

        uint64 firstSequence = lastIssuedSequence + 1;
        Order memory order = Order({
            purchaser: purchaser,
            referrer: referrer,
            fee: fee,
            settlementFee: settlementFee,
            maxNegativeSlippageBps: maxNegativeSlippageBps,
            wordDeadline: uint64(block.number + selectionTimeoutBlocks),
            day: uint64((block.timestamp - ledgerOrigin) / LEDGER_DAY)
        });
        requestIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            requestIds[i] = _openAcquisition(order);
        }
        dayTotals[order.day].accepted += uint64(count);

        if (vrfFee != 0) {
            vrfFeesCollected += vrfFee;
            vrfCoordinator.fundSubscriptionWithNative{value: vrfFee}(vrfSubscriptionId);
            emit VrfFeeCollected(firstSequence, count, vrfFee);
        }
        _requestRandomness(firstSequence, count);

        uint256 excess = msg.value - cost;
        if (excess != 0) SafeTransferLib.forceSafeTransferETH(msg.sender, excess);
    }

    function _validateInventoryCommitment(uint256 expectedInventoryVersion, uint256 deadline) internal view {
        if (block.timestamp > deadline) revert TransactionExpired(deadline);
        uint256 currentVersion = inventoryVersion;
        if (expectedInventoryVersion != ANY_INVENTORY_VERSION && expectedInventoryVersion != currentVersion) {
            revert InventoryVersionMismatch(expectedInventoryVersion, currentVersion);
        }
        uint256 resumeAt = purchasesResumeAt();
        if (block.timestamp < resumeAt) revert InventoryChangeCooldownActive(resumeAt);
    }

    /// @dev Bounded, fixed-output staticcall; fails closed (FWAClone behaviour).
    function _validatePurchaseOperator(address purchaser) internal view {
        address operator = purchaseOperator;
        if (operator == address(0)) return;

        bytes memory callData = abi.encodeCall(IPurchaseOperator.canPurchase, (purchaser));
        bool checked;
        bool allowed;
        uint256 gasStipend = PURCHASE_OPERATOR_GAS;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            checked := staticcall(gasStipend, operator, add(callData, 0x20), mload(callData), ptr, 0x20)
            if iszero(eq(returndatasize(), 0x20)) { checked := 0 }
            if checked {
                let result := mload(ptr)
                if gt(result, 1) { checked := 0 }
                allowed := eq(result, 1)
            }
        }
        if (!checked) revert PurchaseOperatorCheckFailed();
        if (!allowed) revert PurchaseNotAllowed();
    }

    function _validateAcquisition(uint256 maxAcquisitionFee, uint256 minWeightedValue)
        internal
        view
        returns (uint256 fee)
    {
        if (!activated) revert NotActivated();
        if (paused) revert Paused();
        if (retired) revert PoolAlreadyRetired();
        if (totalWeight == 0) revert NoActiveListings();
        if (minWeightedValue != 0 && weightedBackingTotal < minWeightedValue) revert PoolValueTooLow();
        fee = acquisitionFee();
        if (maxAcquisitionFee != 0 && fee > maxAcquisitionFee) revert AcquisitionFeeTooHigh();
    }

    struct Order {
        address purchaser;
        address referrer;
        uint256 fee;
        uint256 settlementFee;
        uint256 maxNegativeSlippageBps;
        uint64 wordDeadline;
        uint64 day;
    }

    function _openAcquisition(Order memory o) internal returns (uint256 requestId) {
        uint64 sequence = ++lastIssuedSequence;
        requestId = sequence;
        uint256 reservedCount = _reserveStagedBatch(sequence);

        acquisitions[requestId] = Acquisition({
            purchaser: o.purchaser,
            requestBlock: block.number,
            priceEscrowed: o.fee,
            listingId: 0,
            status: AcquisitionStatus.Pending
        });
        acquisitionMeta[requestId] = AcquisitionMeta({
            sequence: sequence,
            wordDeadlineBlock: o.wordDeadline,
            ledgerDay: o.day,
            maxPositiveSlippageBps: uint16(selectionSlippageBps),
            maxNegativeSlippageBps: uint16(o.maxNegativeSlippageBps),
            randomWord: 0
        });
        settlementTerms[requestId] = SettlementTerms({
            referrer: o.referrer,
            amount: uint96(o.settlementFee),
            policyId: uint32(_feePolicies.length - 1)
        });

        pendingAcquisitionCount += 1;
        unsettledAcquisitionCount += 1;
        acquisitionEscrowTotal += o.fee + o.settlementFee;

        emit AcquisitionRequested(requestId, o.purchaser, o.fee, o.settlementFee, o.referrer, msg.sender, totalWeight);
        emit AcquisitionSequenced(requestId, sequence, o.wordDeadline, reservedCount);
    }

    /// @dev One VRF request for the batch. The sequence numbers and reservations are committed
    ///      before the external request; a coordinator revert rolls the whole transaction back.
    function _requestRandomness(uint64 firstSequence, uint256 count) internal {
        uint256 gas = callbackGasLimitFor(count);
        uint256 vrfRequestId = vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: uint32(gas),
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );
        if (vrfRequestId == 0 || vrfBatches[vrfRequestId].count != 0) revert DuplicateRequestId();
        vrfBatches[vrfRequestId] = VrfBatch({firstSequence: firstSequence, count: uint32(count), observed: false});
        for (uint256 i; i < count; ++i) {
            vrfRequestOf[firstSequence + i] = vrfRequestId;
        }
        unfulfilledVrfCount += 1;
        emit RandomnessRequested(vrfRequestId, firstSequence, count, uint32(gas));
    }

    /// @notice Clear callback liabilities the coordinator has already completed without a callback.
    function reconcileUnfulfilledVrfCount() external returns (uint256 reconciled) {
        reconciled = unfulfilledVrfCount;
        if (reconciled == 0) return 0;
        if (vrfCoordinator.pendingRequestExists(vrfSubscriptionId)) revert VrfRequestsPending();
        unfulfilledVrfCount = 0;
        emit UnfulfilledVrfReconciled(reconciled);
    }

    /*//////////////////////////////////////////////////////////////
                           CHAINLINK CALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice VRF v2.5 fulfillment entrypoint, coordinator only. Caches one derived word per
    ///         acquisition of the batch (or classifies the batch late), then makes failure-isolated
    ///         attempts to process the canonical head. Never reverts for a known coordinator.
    function rawFulfillRandomWords(uint256 vrfRequestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) revert OnlyCoordinator();
        VrfBatch storage batch = vrfBatches[vrfRequestId];
        uint256 count = batch.count;
        if (count == 0) {
            emit FulfillmentIgnored(vrfRequestId);
            return;
        }
        if (!batch.observed) {
            batch.observed = true;
            uint256 open = unfulfilledVrfCount;
            if (open != 0) unfulfilledVrfCount = open - 1;
        } else {
            emit FulfillmentIgnored(vrfRequestId);
            return;
        }
        if (randomWords.length == 0) {
            emit FulfillmentIgnored(vrfRequestId);
            return;
        }

        uint64 first = batch.firstSequence;
        uint256 word = randomWords[0];
        for (uint256 i; i < count; ++i) {
            uint256 requestId = first + i;
            Acquisition storage acquisition = acquisitions[requestId];
            if (acquisition.status != AcquisitionStatus.Pending) continue;
            AcquisitionMeta storage meta = acquisitionMeta[requestId];
            if (block.number > meta.wordDeadlineBlock) {
                acquisition.status = AcquisitionStatus.TimedOut;
                pendingAcquisitionCount -= 1;
                emit RandomnessTimedOut(requestId, meta.sequence, meta.wordDeadlineBlock, block.number);
                continue;
            }
            uint256 derived = uint256(keccak256(abi.encode(word, i)));
            meta.randomWord = derived;
            acquisition.status = AcquisitionStatus.Ready;
            pendingAcquisitionCount -= 1;
            emit RandomnessCached(requestId, meta.sequence, derived);
        }

        _tryProcessCallbackHead(count);
    }

    /// @dev Best-effort fast path: up to `maxItems` single-item self-calls into the guarded processor,
    ///      each with a fixed stipend. A failure leaves the head `Ready` for a later processor.
    function _tryProcessCallbackHead(uint256 maxItems) internal {
        bytes memory callData = abi.encodeCall(this.processAcquisitions, (1));
        for (uint256 n; n < maxItems; ++n) {
            uint64 head = nextSequenceToProcess;
            if (head > lastIssuedSequence) return;
            if (acquisitions[head].status != AcquisitionStatus.Ready) return;
            if (reservedListingsBySequence[head].length != 0) return;
            if (gasleft() < CALLBACK_FAST_PATH_GAS + CALLBACK_RETURN_GAS_RESERVE) return;
            bool ok;
            uint256 gasStipend = gasleft() - CALLBACK_RETURN_GAS_RESERVE;
            assembly ("memory-safe") {
                ok := call(gasStipend, address(), 0, add(callData, 0x20), mload(callData), 0, 0)
            }
            if (!ok) return;
        }
    }

    /// @notice Process the canonical ready/expired acquisition prefix. Ordering is fixed by
    ///         `nextSequenceToProcess`; the caller chooses only a gas bound.
    function processAcquisitions(uint256 maxCount) external nonReentrant returns (uint256 processed) {
        while (processed < maxCount && nextSequenceToProcess <= lastIssuedSequence) {
            uint64 sequence = nextSequenceToProcess;
            uint256 requestId = sequence;
            Acquisition storage acquisition = acquisitions[requestId];
            AcquisitionMeta storage meta = acquisitionMeta[requestId];
            if (meta.sequence != sequence) revert SequenceInvariantBroken();

            AcquisitionStatus status = acquisition.status;
            if (status == AcquisitionStatus.Pending) {
                if (block.number <= meta.wordDeadlineBlock) break;
                pendingAcquisitionCount -= 1;
                _activateReservedBatch(sequence);
                uint256 refund = _creditAcquisitionRefund(requestId, acquisition, AcquisitionStatus.Expired);
                emit AcquisitionExpired(requestId, sequence, acquisition.purchaser, refund);
            } else if (status == AcquisitionStatus.TimedOut) {
                _activateReservedBatch(sequence);
                uint256 refund = _creditAcquisitionRefund(requestId, acquisition, AcquisitionStatus.Expired);
                emit AcquisitionExpired(requestId, sequence, acquisition.purchaser, refund);
            } else if (status == AcquisitionStatus.Ready) {
                _activateReservedBatch(sequence);
                _settleReadyAcquisition(requestId, acquisition, meta);
            } else {
                revert SequenceInvariantBroken();
            }

            acquisitionEscrowTotal -= acquisition.priceEscrowed + settlementTerms[requestId].amount;
            unsettledAcquisitionCount -= 1;
            emit AcquisitionProcessed(requestId, sequence, acquisition.status, msg.sender);
            unchecked {
                ++nextSequenceToProcess;
                ++processed;
            }
        }
    }

    /// @dev Converts the acquisition fee and settlement fee to the purchaser's pull credit and
    ///      resolves the acquisition's ledger day.
    function _creditAcquisitionRefund(uint256 requestId, Acquisition storage acquisition, AcquisitionStatus status)
        internal
        returns (uint256 refund)
    {
        refund = acquisition.priceEscrowed + settlementTerms[requestId].amount;
        acquisition.status = status;
        acquisitionRefundCredit[acquisition.purchaser] += refund;
        acquisitionRefundCreditTotal += refund;
        dayTotals[acquisitionMeta[requestId].ledgerDay].resolved += 1;
    }

    function _settleReadyAcquisition(uint256 requestId, Acquisition storage acquisition, AcquisitionMeta storage meta)
        internal
    {
        if (totalWeight == 0) {
            uint256 refund = _creditAcquisitionRefund(requestId, acquisition, AcquisitionStatus.Refunded);
            emit AcquisitionRefundedNoListing(requestId, acquisition.purchaser, refund);
            return;
        }

        {
            uint256 liveFee = acquisitionFee();
            uint256 escrowed = acquisition.priceEscrowed;
            uint256 positiveTolerance = escrowed * meta.maxPositiveSlippageBps / BPS;
            uint256 negativeTolerance = escrowed * meta.maxNegativeSlippageBps / BPS;
            if (
                (liveFee > escrowed && liveFee - escrowed > positiveTolerance)
                    || (liveFee < escrowed && escrowed - liveFee > negativeTolerance)
            ) {
                uint256 refund = _creditAcquisitionRefund(requestId, acquisition, AcquisitionStatus.Refunded);
                emit AcquisitionRefundedSlippage(requestId, acquisition.purchaser, refund, escrowed, liveFee);
                return;
            }
        }

        uint256 randomWord = meta.randomWord;
        uint256 target = randomWord % totalWeight;
        uint256 slot = _selectSlot(target);
        uint256 listingId = slotToListing[slot];
        if (listingId == 0) revert InvalidTreeResult();
        Listing storage listing = listings[listingId];
        if (listing.status != ListingStatus.Active) revert InvalidTreeResult();

        _settleAndRemove(listingId);
        listing.purchaser = acquisition.purchaser;
        listing.status = ListingStatus.DeliveryPending;
        acquisition.listingId = listingId;
        acquisition.status = AcquisitionStatus.DeliveryPending;

        pendingDeliveries[listingId] =
            PendingDelivery({requestId: requestId, deadline: uint64(block.timestamp + DELIVERY_WINDOW)});
        deliveryEscrowTotal += acquisition.priceEscrowed + settlementTerms[requestId].amount;

        emit NFTAllocated(requestId, listingId, acquisition.purchaser, listing.depositor, listing.price, randomWord);

        if (_tryAtomicNFTDelivery(listingId)) {
            _completeNFTDelivery(listingId);
        } else {
            emit NFTDeliveryFailed(listingId, acquisition.purchaser, listing.collection, listing.tokenId);
        }
    }

    /// @notice Pull acquisition and settlement fees credited by expiry, empty-pool, slippage or
    ///         delivery refunds.
    function withdrawAcquisitionRefund() external nonReentrant returns (uint256 amount) {
        amount = acquisitionRefundCredit[msg.sender];
        if (amount == 0) revert NoAcquisitionRefund();
        acquisitionRefundCredit[msg.sender] = 0;
        acquisitionRefundCreditTotal -= amount;
        SafeTransferLib.forceSafeTransferETH(msg.sender, amount);
        emit AcquisitionRefundWithdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         NFT DELIVERY ESCROW
    //////////////////////////////////////////////////////////////*/

    /// @notice Permissionlessly retry the exact selected NFT-to-purchaser delivery without a gas stipend.
    function retryNFTDelivery(uint256 listingId) external nonReentrant {
        if (listings[listingId].status != ListingStatus.DeliveryPending) revert DeliveryNotPending();
        if (block.timestamp >= pendingDeliveries[listingId].deadline) revert DeliveryWindowElapsed();
        this.executeNFTDelivery(listingId);
        _completeNFTDelivery(listingId);
    }

    /// @notice After the delivery window, convert the escrow to the purchaser's pull refund. Anyone
    ///         may call it (FWAClone limits it to the purchaser); the credit always goes to the purchaser.
    function refundFailedDelivery(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status != ListingStatus.DeliveryPending) revert DeliveryNotPending();
        PendingDelivery memory delivery = pendingDeliveries[listingId];
        if (block.timestamp < delivery.deadline) revert DeliveryWindowNotElapsed();

        uint256 requestId = delivery.requestId;
        Acquisition storage acquisition = acquisitions[requestId];
        uint256 refund = acquisition.priceEscrowed + settlementTerms[requestId].amount;
        deliveryEscrowTotal -= refund;
        address purchaser = listing.purchaser;
        acquisitionRefundCredit[purchaser] += refund;
        acquisitionRefundCreditTotal += refund;
        listing.status = ListingStatus.DeliveryRefunded;
        acquisition.status = AcquisitionStatus.DeliveryRefunded;
        dayTotals[acquisitionMeta[requestId].ledgerDay].resolved += 1;

        delete pendingDeliveries[listingId];
        emit NFTDeliveryRefunded(listingId, requestId, purchaser, refund);
    }

    /// @notice The depositor recovers a quarantined NFT after its purchaser was refunded.
    function recoverRefundedNFT(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.status != ListingStatus.DeliveryRefunded) revert DeliveryNotRefunded();
        if (msg.sender != listing.depositor) revert NotDepositor();
        this.executeNFTDelivery(listingId);
        listing.status = ListingStatus.Withdrawn;
        emit RefundedNFTRecovered(listingId, msg.sender);
    }

    /// @dev Narrow child frame: controller clear, transfer and ownership verification commit together.
    function executeNFTDelivery(uint256 listingId) external {
        if (msg.sender != address(this)) revert OnlySelf();
        Listing storage listing = listings[listingId];
        address recipient;
        if (listing.status == ListingStatus.DeliveryPending) {
            recipient = listing.purchaser;
        } else if (listing.status == ListingStatus.DeliveryRefunded) {
            recipient = listing.depositor;
        } else {
            revert DeliveryNotPending();
        }
        address collection = listing.collection;
        uint256 tokenId = listing.tokenId;
        if (liveNFTListing[collection][tokenId] != listingId) revert StaleNFTController();
        delete liveNFTListing[collection][tokenId];
        IERC721Minimal(collection).transferFrom(address(this), recipient, tokenId);
        if (IERC721Minimal(collection).ownerOf(tokenId) != recipient) revert NFTTransferFailed();
    }

    function _tryAtomicNFTDelivery(uint256 listingId) internal returns (bool success) {
        bytes memory callData = abi.encodeCall(this.executeNFTDelivery, (listingId));
        uint256 gasStipend = NFT_DELIVERY_GAS;
        assembly ("memory-safe") {
            success := call(gasStipend, address(), 0, add(callData, 0x20), mload(callData), 0, 0)
        }
    }

    /// @dev Verified delivery: the full acquisition fee accrues to the listing's depositor, the
    ///      settlement fee is split by the request's policy, and the purchaser earns one unit and
    ///      a bonus weight on the request's ledger day.
    function _completeNFTDelivery(uint256 listingId) internal {
        Listing storage listing = listings[listingId];
        if (listing.status != ListingStatus.DeliveryPending) revert DeliveryNotPending();
        PendingDelivery memory delivery = pendingDeliveries[listingId];
        uint256 requestId = delivery.requestId;
        Acquisition storage acquisition = acquisitions[requestId];
        SettlementTerms memory terms = settlementTerms[requestId];
        uint256 paid = acquisition.priceEscrowed;

        deliveryEscrowTotal -= paid + terms.amount;
        address depositor = listing.depositor;
        proceedsOf[depositor] += paid;
        proceedsTotal += paid;
        listing.status = ListingStatus.Settled;
        acquisition.status = AcquisitionStatus.Fulfilled;
        delete pendingDeliveries[listingId];

        _splitSettlementFee(requestId, terms);
        _recordParticipation(requestId, acquisition.purchaser);

        emit ProceedsAccrued(requestId, depositor, paid);
        emit NFTDeliveryCompleted(listingId, requestId, listing.purchaser);
    }

    function _splitSettlementFee(uint256 requestId, SettlementTerms memory terms) internal {
        uint256 amount = terms.amount;
        if (amount == 0) return;
        FeePolicy memory policy = _feePolicies[terms.policyId];
        uint256 toReferrer = amount * policy.referrerBps / BPS;
        uint256 toTokenWorks = amount * policy.tokenWorksBps / BPS;
        uint256 toDev = amount - toReferrer - toTokenWorks;
        address referrer = terms.referrer;
        if (referrer == address(0)) {
            toDev += toReferrer;
            toReferrer = 0;
        } else {
            feeCreditOf[referrer] += toReferrer;
        }
        feeCreditOf[tokenWorksRecipient] += toTokenWorks;
        feeCreditOf[devRecipient] += toDev;
        feeCreditTotal += amount;
        emit SettlementFeeSplit(requestId, referrer, toReferrer, toTokenWorks, toDev);
    }

    function _recordParticipation(uint256 requestId, address purchaser) internal {
        AcquisitionMeta storage meta = acquisitionMeta[requestId];
        uint256 day = meta.ledgerDay;
        uint64 bonus = uint64(bonusWeightOf(meta.randomWord));
        DayTotals storage totals = dayTotals[day];
        totals.resolved += 1;
        totals.units += 1;
        totals.bonusWeight += bonus;
        UserDay storage u = userDay[day][purchaser];
        u.units += 1;
        u.bonusWeight += bonus;
        emit ParticipationRecorded(day, purchaser, requestId, bonus);
    }

    /// @notice Bonus weight of a fulfilled acquisition from its selection word: 25 with
    ///         probability 1%, 5 with probability 9%, otherwise 1. The word is the VRF-derived word
    ///         that selected the prize, so the bonus cannot be chosen or rerolled.
    function bonusWeightOf(uint256 randomWord) public pure returns (uint256) {
        uint256 r = uint256(keccak256(abi.encode(randomWord, "bonus"))) % 1_000;
        if (r < 10) return 25;
        if (r < 100) return 5;
        return 1;
    }

    /*//////////////////////////////////////////////////////////////
                         PROCEEDS AND FEE CREDITS
    //////////////////////////////////////////////////////////////*/

    /// @notice A depositor withdraws its accrued acquisition proceeds.
    function withdrawProceeds() external nonReentrant returns (uint256 amount) {
        amount = proceedsOf[msg.sender];
        if (amount == 0) revert NoProceeds();
        proceedsOf[msg.sender] = 0;
        proceedsTotal -= amount;
        SafeTransferLib.forceSafeTransferETH(msg.sender, amount);
        emit ProceedsWithdrawn(msg.sender, amount);
    }

    /// @notice A settlement-fee recipient (referrer, Token Works, development) withdraws its credit.
    function withdrawFeeCredit(address to) external nonReentrant returns (uint256 amount) {
        if (to == address(0)) revert InvalidConfig();
        amount = feeCreditOf[msg.sender];
        if (amount == 0) revert NoFeeCredit();
        feeCreditOf[msg.sender] = 0;
        feeCreditTotal -= amount;
        SafeTransferLib.forceSafeTransferETH(to, amount);
        emit FeeCreditWithdrawn(msg.sender, to, amount);
    }

    /// @notice ETH the engine must hold for its obligations. `address(this).balance` is at least this.
    function liabilities() public view returns (uint256) {
        return acquisitionEscrowTotal + deliveryEscrowTotal + acquisitionRefundCreditTotal + proceedsTotal
            + feeCreditTotal;
    }

    function _settleAndRemove(uint256 listingId) internal {
        Listing storage listing = listings[listingId];
        uint256 slot = listing.slot;
        _removeTreeWeight(slot, listing.weight);
        totalWeight -= listing.weight;
        weightedBackingTotal -= listing.weight * listing.price;
        activeListingCount--;
        delete slotToListing[slot];
        _releaseSlot(slot);
        listing.slot = 0;
    }

    /*//////////////////////////////////////////////////////////////
                          SEGMENT TREE
    //////////////////////////////////////////////////////////////*/

    function _addTreeWeight(uint256 slot, uint256 amount) internal {
        uint256 node = LEAF_BASE + slot - 1;
        while (true) {
            tree[node] += amount;
            if (node == 1) break;
            node >>= 1;
        }
    }

    function _removeTreeWeight(uint256 slot, uint256 amount) internal {
        uint256 node = LEAF_BASE + slot - 1;
        while (true) {
            tree[node] -= amount;
            if (node == 1) break;
            node >>= 1;
        }
    }

    function _selectSlot(uint256 target) internal view returns (uint256 slot) {
        uint256 node = 1;
        while (node < LEAF_BASE) {
            uint256 leftChild = node << 1;
            uint256 leftWeight = tree[leftChild];
            if (target < leftWeight) {
                node = leftChild;
            } else {
                target -= leftWeight;
                node = leftChild | 1;
            }
        }
        slot = node - LEAF_BASE + 1;
    }

    function _allocateSlot() internal returns (uint256 slot) {
        if (freeSlotHead != 0) {
            slot = freeSlotHead;
            freeSlotHead = nextFreeSlot[slot];
            delete nextFreeSlot[slot];
            return slot;
        }
        slot = nextUnusedSlot++;
        if (slot > CAPACITY) revert ActiveListingCapacityReached();
    }

    function _releaseSlot(uint256 slot) internal {
        nextFreeSlot[slot] = freeSlotHead;
        freeSlotHead = slot;
    }

    function treeRootWeight() external view returns (uint256) {
        return tree[1];
    }

    /*//////////////////////////////////////////////////////////////
                          LEDGER VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ledger day of `timestamp`. Reverts before activation.
    function ledgerDayOf(uint256 timestamp) external view returns (uint256) {
        if (!activated) revert NotActivated();
        return (timestamp - ledgerOrigin) / LEDGER_DAY;
    }

    /// @notice Accepted acquisitions of `day` not yet terminal (fulfilled or refunded).
    function dayOpen(uint256 day) external view returns (uint256) {
        DayTotals memory t = dayTotals[day];
        return t.accepted - t.resolved;
    }

    function feePolicy(uint256 policyId) external view returns (FeePolicy memory) {
        return _feePolicies[policyId];
    }

    function feePolicyCount() external view returns (uint256) {
        return _feePolicies.length;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Open the game: acquisitions become possible and the ledger starts. One time only.
    function activate() external onlyGovernance {
        if (activated) revert AlreadyActivated();
        if (retired) revert PoolAlreadyRetired();
        activated = true;
        ledgerOrigin = uint64(block.timestamp);
        emit Activated(uint64(block.timestamp));
    }

    /// @notice Pause or unpause new acquisitions. Guardian or governance.
    function setPaused(bool value) external {
        if (msg.sender != guardian && msg.sender != governance) revert NotGuardian();
        paused = value;
        emit PausedSet(value);
    }

    /// @notice Permanently close the engine to new acquisitions and inventory. Processing,
    ///         delivery, refunds and withdrawals stay available.
    function retire() external onlyGovernance {
        if (retired) revert PoolAlreadyRetired();
        retired = true;
        emit Retired();
    }

    function proposeGovernance(address next) external onlyGovernance {
        pendingGovernance = next;
        emit GovernanceProposed(next);
    }

    function acceptGovernance() external {
        if (msg.sender != pendingGovernance || msg.sender == address(0)) revert NotGovernance();
        emit GovernanceTransferred(governance, msg.sender);
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function setGuardian(address next) external onlyGovernance {
        if (next == address(0)) revert InvalidConfig();
        guardian = next;
        emit GuardianSet(next);
    }

    function setSupplier(address supplier, bool allowed) external onlyGovernance {
        if (supplier == address(0) || supplier.code.length == 0) revert InvalidConfig();
        isSupplier[supplier] = allowed;
        emit SupplierSet(supplier, allowed);
    }

    function setPurchaseOperator(address newOperator) external onlyGovernance {
        if (newOperator != address(0) && newOperator.code.length == 0) revert InvalidPurchaseOperator();
        emit PurchaseOperatorSet(purchaseOperator, newOperator);
        purchaseOperator = newOperator;
    }

    /// @notice Adds a fee policy that applies to acquisitions requested from now on. Earlier
    ///         requests settle under the policy they were requested with.
    function setFeePolicy(uint256 settlementBps, uint16 referrerBps, uint16 tokenWorksBps) external onlyGovernance {
        _setFeePolicy(settlementBps, referrerBps, tokenWorksBps);
    }

    function setFeeRecipients(address tokenWorks, address dev) external onlyGovernance {
        _setFeeRecipients(tokenWorks, dev);
    }

    function setLimits(Limits calldata limits) external onlyGovernance {
        _setLimits(limits);
    }

    /// @notice Replace the VRF configuration. Only while no request is outstanding.
    function setVrfConfig(VrfConfig calldata vrf) external onlyGovernance {
        if (unsettledAcquisitionCount != 0 || unfulfilledVrfCount != 0) revert AcquisitionStateLocked();
        _setVrfConfig(vrf);
    }

    function setVrfFeeConfig(VrfFeeConfig calldata c) external onlyGovernance {
        _setVrfFeeConfig(c);
    }

    function _setVrfFeeConfig(VrfFeeConfig memory c) internal {
        if (c.premiumBps > MAX_VRF_PREMIUM_BPS || c.bufferBps > MAX_VRF_BUFFER_BPS || c.flatWei > MAX_VRF_FEE_PER_BATCH) {
            revert InvalidConfig();
        }
        vrfFeeConfig = c;
        emit VrfFeeConfigSet(c);
    }

    function _setFeePolicy(uint256 settlementBps, uint16 referrerBps, uint16 tokenWorksBps) internal {
        if (settlementBps > MAX_SETTLEMENT_FEE_BPS || uint256(referrerBps) + tokenWorksBps > BPS) {
            revert InvalidConfig();
        }
        settlementFeeBps = settlementBps;
        _feePolicies.push(FeePolicy({referrerBps: referrerBps, tokenWorksBps: tokenWorksBps}));
        emit FeePolicySet(_feePolicies.length - 1, settlementBps, referrerBps, tokenWorksBps);
    }

    function _setFeeRecipients(address tokenWorks, address dev) internal {
        if (tokenWorks == address(0) || dev == address(0)) revert InvalidConfig();
        tokenWorksRecipient = tokenWorks;
        devRecipient = dev;
        emit FeeRecipientsSet(tokenWorks, dev);
    }

    function _setLimits(Limits memory l) internal {
        if (
            l.maxAcquisitionsPerTx == 0 || l.maxAcquisitionsPerTx > MAX_ACQUISITIONS_PER_TX_CAP
                || l.maxUnsettledAcquisitions < l.maxAcquisitionsPerTx || l.maxUnsettledAcquisitions > MAX_UNSETTLED_CAP
                || l.maxActivationsPerAcquisition == 0 || l.maxActivationsPerAcquisition > MAX_ACTIVATIONS_PER_ACQUISITION
                || l.selectionSlippageBps > BPS || l.inventoryChangeCooldown > MAX_INVENTORY_COOLDOWN
        ) revert InvalidConfig();
        maxAcquisitionsPerTx = l.maxAcquisitionsPerTx;
        maxUnsettledAcquisitions = l.maxUnsettledAcquisitions;
        maxActivationsPerAcquisition = l.maxActivationsPerAcquisition;
        selectionSlippageBps = l.selectionSlippageBps;
        inventoryChangeCooldown = l.inventoryChangeCooldown;
        emit LimitsSet(
            l.maxAcquisitionsPerTx,
            l.maxUnsettledAcquisitions,
            l.maxActivationsPerAcquisition,
            l.selectionSlippageBps,
            l.inventoryChangeCooldown
        );
    }

    function _setVrfConfig(VrfConfig memory v) internal {
        if (
            v.coordinator == address(0) || v.coordinator.code.length == 0 || v.subscriptionId == 0
                || v.keyHash == bytes32(0) || v.requestConfirmations < MIN_REQUEST_CONFIRMATIONS
                || v.requestConfirmations > MAX_REQUEST_CONFIRMATIONS
                || uint256(v.callbackGasBase) + v.callbackGasPerAcquisition < MIN_CALLBACK_GAS_LIMIT
                || v.callbackGasBase > MAX_CALLBACK_GAS_LIMIT || v.callbackGasPerAcquisition > MAX_CALLBACK_GAS_LIMIT
                || v.selectionTimeoutBlocks < uint256(v.requestConfirmations) + MIN_CALLBACK_SLACK_BLOCKS
                || v.selectionTimeoutBlocks > MAX_WINDOW_BLOCKS
        ) revert InvalidConfig();
        vrfCoordinator = IVRFCoordinatorV2Plus(v.coordinator);
        vrfSubscriptionId = v.subscriptionId;
        vrfKeyHash = v.keyHash;
        requestConfirmations = v.requestConfirmations;
        callbackGasBase = v.callbackGasBase;
        callbackGasPerAcquisition = v.callbackGasPerAcquisition;
        selectionTimeoutBlocks = v.selectionTimeoutBlocks;
        emit VrfConfigSet(
            v.coordinator,
            v.subscriptionId,
            v.keyHash,
            v.requestConfirmations,
            v.callbackGasBase,
            v.callbackGasPerAcquisition,
            v.selectionTimeoutBlocks
        );
    }
}
