// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "./interfaces/IVRFCoordinatorV2Plus.sol";
import {IGame} from "../interfaces/IGame.sol";
import {IGameRegistry} from "../interfaces/IGameRegistry.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title VRFConsumer - Centralized VRF Manager for Casino Games
/// @notice Manages VRF requests and callbacks for all registered games
/// @dev UUPS upgradeable, integrates with Chainlink VRF V2.5
contract VRFConsumer is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    // ============ Constants ============

    /// @notice Role for requesting randomness
    bytes32 public constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ============ Structs ============

    /// @notice VRF request details
    struct VRFRequest {
        address game;
        uint256 betId;
        uint64 timestamp;
        bool fulfilled;
    }

    /// @notice VRF configuration
    struct VRFConfig {
        bytes32 keyHash;
        uint256 subscriptionId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bool nativePayment;
    }

    // ============ Storage ============

    /// @notice VRF Coordinator contract
    IVRFCoordinatorV2Plus public vrfCoordinator;

    /// @notice Game Registry contract
    IGameRegistry public gameRegistry;

    /// @notice VRF configuration
    VRFConfig public vrfConfig;

    /// @notice Mapping from VRF request ID to request details
    mapping(uint256 => VRFRequest) public vrfRequests;

    /// @notice Mapping from game + betId to VRF request ID
    mapping(address => mapping(uint256 => uint256)) public betToRequestId;

    /// @notice Total requests made
    uint256 public totalRequests;

    /// @notice Total requests fulfilled
    uint256 public totalFulfilled;

    /// @notice Storage gap for future upgrades
    uint256[40] private __gap;

    // ============ Events ============

    /// @notice Emitted when randomness is requested
    event RandomnessRequested(
        uint256 indexed requestId, address indexed game, uint256 indexed betId, uint32 numWords
    );

    /// @notice Emitted when randomness is fulfilled
    event RandomnessFulfilled(uint256 indexed requestId, address indexed game, uint256 indexed betId);

    /// @notice Emitted when VRF config is updated
    event VRFConfigUpdated(bytes32 keyHash, uint256 subscriptionId, uint32 callbackGasLimit);

    /// @notice Emitted when coordinator is updated
    event CoordinatorUpdated(address indexed oldCoordinator, address indexed newCoordinator);

    // ============ Errors ============

    /// @notice Only coordinator can fulfill
    error OnlyCoordinatorCanFulfill(address caller, address coordinator);

    /// @notice Request not found
    error RequestNotFound(uint256 requestId);

    /// @notice Request already fulfilled
    error RequestAlreadyFulfilled(uint256 requestId);

    /// @notice Invalid game address
    error InvalidGame(address game);

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initialize the VRF consumer
    /// @param admin Admin address
    /// @param coordinator VRF Coordinator address
    /// @param registry Game registry address
    /// @param keyHash VRF key hash
    /// @param subscriptionId VRF subscription ID
    /// @param callbackGasLimit Gas limit for callback
    function initialize(
        address admin,
        address coordinator,
        address registry,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();
        if (coordinator == address(0)) revert Errors.InvalidAddress();
        if (registry == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        vrfCoordinator = IVRFCoordinatorV2Plus(coordinator);
        gameRegistry = IGameRegistry(registry);

        vrfConfig = VRFConfig({
            keyHash: keyHash,
            subscriptionId: subscriptionId,
            requestConfirmations: 3,
            callbackGasLimit: callbackGasLimit,
            numWords: 1,
            nativePayment: false
        });
    }

    // ============ External Functions ============

    /// @notice Request randomness for a bet
    /// @param game The game contract requesting randomness
    /// @param betId The bet ID to resolve
    /// @return requestId The VRF request ID
    function requestRandomness(address game, uint256 betId)
        external
        whenNotPaused
        returns (uint256 requestId)
    {
        // Verify caller is the game or has requester role
        if (msg.sender != game && !hasRole(REQUESTER_ROLE, msg.sender)) {
            revert Errors.Unauthorized();
        }

        // Verify game is registered
        if (!gameRegistry.isRegisteredGame(game)) {
            revert InvalidGame(game);
        }

        // Check if request already exists for this bet
        if (betToRequestId[game][betId] != 0) {
            return betToRequestId[game][betId];
        }

        // Build the request
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: vrfConfig.keyHash,
            subId: vrfConfig.subscriptionId,
            requestConfirmations: vrfConfig.requestConfirmations,
            callbackGasLimit: vrfConfig.callbackGasLimit,
            numWords: vrfConfig.numWords,
            extraArgs: VRFV2PlusClient.extraArgsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: vrfConfig.nativePayment})
            )
        });

        // Request random words
        requestId = vrfCoordinator.requestRandomWords(request);

        // Store request details
        vrfRequests[requestId] = VRFRequest({
            game: game,
            betId: betId,
            timestamp: uint64(block.timestamp),
            fulfilled: false
        });

        betToRequestId[game][betId] = requestId;
        totalRequests++;

        emit RandomnessRequested(requestId, game, betId, vrfConfig.numWords);
    }

    /// @notice Callback function for VRF coordinator
    /// @dev Only callable by the VRF coordinator
    /// @param requestId The request ID
    /// @param randomWords The random values
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(vrfCoordinator));
        }

        VRFRequest storage request = vrfRequests[requestId];

        if (request.game == address(0)) {
            revert RequestNotFound(requestId);
        }

        if (request.fulfilled) {
            revert RequestAlreadyFulfilled(requestId);
        }

        request.fulfilled = true;
        totalFulfilled++;

        // Forward randomness to the game for bet resolution
        IGame(request.game).resolveBet(request.betId, randomWords);

        emit RandomnessFulfilled(requestId, request.game, request.betId);
    }

    // ============ View Functions ============

    /// @notice Get request details
    /// @param requestId The request ID
    /// @return The VRF request struct
    function getRequest(uint256 requestId) external view returns (VRFRequest memory) {
        return vrfRequests[requestId];
    }

    /// @notice Get request ID for a game bet
    /// @param game The game address
    /// @param betId The bet ID
    /// @return The request ID (0 if none)
    function getRequestId(address game, uint256 betId) external view returns (uint256) {
        return betToRequestId[game][betId];
    }

    /// @notice Check if a request is pending
    /// @param requestId The request ID
    /// @return True if pending (not fulfilled)
    function isPending(uint256 requestId) external view returns (bool) {
        VRFRequest storage request = vrfRequests[requestId];
        return request.game != address(0) && !request.fulfilled;
    }

    /// @notice Get VRF statistics
    /// @return requests Total requests
    /// @return fulfilled Total fulfilled
    /// @return pending Total pending
    function getStats() external view returns (uint256 requests, uint256 fulfilled, uint256 pending) {
        return (totalRequests, totalFulfilled, totalRequests - totalFulfilled);
    }

    // ============ Admin Functions ============

    /// @notice Update VRF configuration
    /// @param keyHash New key hash
    /// @param subscriptionId New subscription ID
    /// @param requestConfirmations New confirmations
    /// @param callbackGasLimit New gas limit
    /// @param numWords New number of words
    /// @param nativePayment Whether to use native payment
    function setVRFConfig(
        bytes32 keyHash,
        uint256 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        bool nativePayment
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vrfConfig = VRFConfig({
            keyHash: keyHash,
            subscriptionId: subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            nativePayment: nativePayment
        });

        emit VRFConfigUpdated(keyHash, subscriptionId, callbackGasLimit);
    }

    /// @notice Update VRF coordinator address
    /// @param newCoordinator New coordinator address
    function setCoordinator(address newCoordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newCoordinator == address(0)) revert Errors.InvalidAddress();

        address oldCoordinator = address(vrfCoordinator);
        vrfCoordinator = IVRFCoordinatorV2Plus(newCoordinator);

        emit CoordinatorUpdated(oldCoordinator, newCoordinator);
    }

    /// @notice Update game registry address
    /// @param newRegistry New registry address
    function setGameRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry == address(0)) revert Errors.InvalidAddress();
        gameRegistry = IGameRegistry(newRegistry);
    }

    /// @notice Grant requester role to a game
    /// @param game The game address
    function addRequester(address game) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REQUESTER_ROLE, game);
    }

    /// @notice Revoke requester role from a game
    /// @param game The game address
    function removeRequester(address game) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(REQUESTER_ROLE, game);
    }

    /// @notice Pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============ Internal Functions ============

    /// @notice Authorize upgrade
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
