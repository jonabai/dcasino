// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VRFConsumer} from "../../src/chainlink/VRFConsumer.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {Treasury} from "../../src/Treasury.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockVRFCoordinator} from "../mocks/MockVRFCoordinator.sol";
import {MockGame} from "../mocks/MockGame.sol";

contract VRFConsumerTest is Test {
    VRFConsumer public vrfConsumerImpl;
    VRFConsumer public vrfConsumer;
    GameRegistry public registryImpl;
    GameRegistry public registry;
    Treasury public treasuryImpl;
    Treasury public treasury;
    MockVRFCoordinator public vrfCoordinator;
    MockGame public mockGame;

    address public admin = makeAddr("admin");
    address public player = makeAddr("player");

    bytes32 public constant KEY_HASH = keccak256("key_hash");
    uint256 public constant SUBSCRIPTION_ID = 1;
    uint32 public constant CALLBACK_GAS_LIMIT = 500000;

    event RandomnessRequested(
        uint256 indexed requestId, address indexed game, uint256 indexed betId, uint32 numWords
    );
    event RandomnessFulfilled(uint256 indexed requestId, address indexed game, uint256 indexed betId);

    function setUp() public {
        // Deploy VRF Coordinator mock
        vrfCoordinator = new MockVRFCoordinator();

        // Deploy Treasury
        treasuryImpl = new Treasury();
        bytes memory treasuryInitData = abi.encodeWithSelector(Treasury.initialize.selector, admin);
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImpl), treasuryInitData);
        treasury = Treasury(payable(address(treasuryProxy)));

        // Deploy GameRegistry
        registryImpl = new GameRegistry();
        bytes memory registryInitData =
            abi.encodeWithSelector(GameRegistry.initialize.selector, admin, address(treasury));
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        registry = GameRegistry(address(registryProxy));

        // Deploy VRFConsumer
        vrfConsumerImpl = new VRFConsumer();
        bytes memory vrfInitData = abi.encodeWithSelector(
            VRFConsumer.initialize.selector,
            admin,
            address(vrfCoordinator),
            address(registry),
            KEY_HASH,
            SUBSCRIPTION_ID,
            CALLBACK_GAS_LIMIT
        );
        ERC1967Proxy vrfProxy = new ERC1967Proxy(address(vrfConsumerImpl), vrfInitData);
        vrfConsumer = VRFConsumer(address(vrfProxy));

        // Deploy MockGame
        mockGame = new MockGame("TestGame", address(0), address(treasury), address(registry));

        // Setup: Register game and grant roles
        vm.startPrank(admin);
        registry.registerGame(address(mockGame), "TestGame");
        vrfConsumer.addRequester(address(mockGame));
        // Grant resolver role to VRF consumer on the mock game
        vm.stopPrank();

        // Fund treasury
        vm.deal(admin, 100 ether);
        vm.prank(admin);
        treasury.deposit{value: 100 ether}();

        // Fund player
        vm.deal(player, 10 ether);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertTrue(vrfConsumer.hasRole(vrfConsumer.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vrfConsumer.hasRole(vrfConsumer.UPGRADER_ROLE(), admin));
        assertEq(address(vrfConsumer.vrfCoordinator()), address(vrfCoordinator));
        assertEq(address(vrfConsumer.gameRegistry()), address(registry));

        (
            bytes32 keyHash,
            uint256 subId,
            uint16 confirmations,
            uint32 gasLimit,
            uint32 numWords,
            bool nativePayment
        ) = vrfConsumer.vrfConfig();

        assertEq(keyHash, KEY_HASH);
        assertEq(subId, SUBSCRIPTION_ID);
        assertEq(confirmations, 3);
        assertEq(gasLimit, CALLBACK_GAS_LIMIT);
        assertEq(numWords, 1);
        assertFalse(nativePayment);
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        VRFConsumer newImpl = new VRFConsumer();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                VRFConsumer.initialize.selector,
                address(0),
                address(vrfCoordinator),
                address(registry),
                KEY_HASH,
                SUBSCRIPTION_ID,
                CALLBACK_GAS_LIMIT
            )
        );
    }

    // ============ Request Randomness Tests ============

    function test_RequestRandomness() public {
        uint256 betId = 1;

        vm.prank(address(mockGame));
        vm.expectEmit(true, true, true, true);
        emit RandomnessRequested(1, address(mockGame), betId, 1);
        uint256 requestId = vrfConsumer.requestRandomness(address(mockGame), betId);

        assertEq(requestId, 1);
        assertEq(vrfConsumer.getRequestId(address(mockGame), betId), requestId);

        VRFConsumer.VRFRequest memory request = vrfConsumer.getRequest(requestId);
        assertEq(request.game, address(mockGame));
        assertEq(request.betId, betId);
        assertFalse(request.fulfilled);
    }

    function test_RequestRandomnessIdempotent() public {
        uint256 betId = 1;

        vm.prank(address(mockGame));
        uint256 requestId1 = vrfConsumer.requestRandomness(address(mockGame), betId);

        // Second request for same bet should return same ID
        vm.prank(address(mockGame));
        uint256 requestId2 = vrfConsumer.requestRandomness(address(mockGame), betId);

        assertEq(requestId1, requestId2);
    }

    function test_RevertWhen_RequestRandomnessUnauthorized() public {
        vm.prank(player);
        vm.expectRevert(Errors.Unauthorized.selector);
        vrfConsumer.requestRandomness(address(mockGame), 1);
    }

    function test_RevertWhen_RequestRandomnessUnregisteredGame() public {
        MockGame unregisteredGame = new MockGame("Unregistered", address(0), address(treasury), address(registry));

        vm.prank(address(unregisteredGame));
        vm.expectRevert(abi.encodeWithSelector(VRFConsumer.InvalidGame.selector, address(unregisteredGame)));
        vrfConsumer.requestRandomness(address(unregisteredGame), 1);
    }

    // ============ Fulfill Randomness Tests ============

    function test_FulfillRandomness() public {
        uint256 betId = 1;

        // First, player places a bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Request randomness
        vm.prank(address(mockGame));
        uint256 requestId = vrfConsumer.requestRandomness(address(mockGame), betId);

        // Fulfill from coordinator
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        vm.expectEmit(true, true, true, false);
        emit RandomnessFulfilled(requestId, address(mockGame), betId);
        vrfCoordinator.fulfillRandomWords(requestId, randomWords);

        // Verify fulfilled
        VRFConsumer.VRFRequest memory request = vrfConsumer.getRequest(requestId);
        assertTrue(request.fulfilled);
    }

    function test_RevertWhen_FulfillNotFromCoordinator() public {
        vm.prank(player);
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        vm.expectRevert(
            abi.encodeWithSelector(VRFConsumer.OnlyCoordinatorCanFulfill.selector, player, address(vrfCoordinator))
        );
        vrfConsumer.rawFulfillRandomWords(1, randomWords);
    }

    function test_RevertWhen_FulfillNonexistentRequest() public {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        vm.expectRevert(abi.encodeWithSelector(VRFConsumer.RequestNotFound.selector, 999));
        vm.prank(address(vrfCoordinator));
        vrfConsumer.rawFulfillRandomWords(999, randomWords);
    }

    // ============ View Function Tests ============

    function test_IsPending() public {
        uint256 betId = 1;

        vm.prank(address(mockGame));
        uint256 requestId = vrfConsumer.requestRandomness(address(mockGame), betId);

        assertTrue(vrfConsumer.isPending(requestId));

        // Fulfill
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;
        vrfCoordinator.fulfillRandomWords(requestId, randomWords);

        assertFalse(vrfConsumer.isPending(requestId));
    }

    function test_GetStats() public {
        // Request multiple
        vm.startPrank(address(mockGame));
        vrfConsumer.requestRandomness(address(mockGame), 1);
        vrfConsumer.requestRandomness(address(mockGame), 2);
        vrfConsumer.requestRandomness(address(mockGame), 3);
        vm.stopPrank();

        (uint256 requests, uint256 fulfilled, uint256 pending) = vrfConsumer.getStats();
        assertEq(requests, 3);
        assertEq(fulfilled, 0);
        assertEq(pending, 3);

        // Fulfill one
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;
        vrfCoordinator.fulfillRandomWords(1, randomWords);

        (requests, fulfilled, pending) = vrfConsumer.getStats();
        assertEq(requests, 3);
        assertEq(fulfilled, 1);
        assertEq(pending, 2);
    }

    // ============ Admin Function Tests ============

    function test_SetVRFConfig() public {
        bytes32 newKeyHash = keccak256("new_key_hash");
        uint256 newSubId = 999;
        uint16 newConfirmations = 5;
        uint32 newGasLimit = 1000000;
        uint32 newNumWords = 3;
        bool newNativePayment = true;

        vm.prank(admin);
        vrfConsumer.setVRFConfig(
            newKeyHash, newSubId, newConfirmations, newGasLimit, newNumWords, newNativePayment
        );

        (
            bytes32 keyHash,
            uint256 subId,
            uint16 confirmations,
            uint32 gasLimit,
            uint32 numWords,
            bool nativePayment
        ) = vrfConsumer.vrfConfig();

        assertEq(keyHash, newKeyHash);
        assertEq(subId, newSubId);
        assertEq(confirmations, newConfirmations);
        assertEq(gasLimit, newGasLimit);
        assertEq(numWords, newNumWords);
        assertTrue(nativePayment);
    }

    function test_SetCoordinator() public {
        address newCoordinator = makeAddr("newCoordinator");

        vm.prank(admin);
        vrfConsumer.setCoordinator(newCoordinator);

        assertEq(address(vrfConsumer.vrfCoordinator()), newCoordinator);
    }

    function test_RevertWhen_SetCoordinatorZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        vrfConsumer.setCoordinator(address(0));
    }

    function test_SetGameRegistry() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(admin);
        vrfConsumer.setGameRegistry(newRegistry);

        assertEq(address(vrfConsumer.gameRegistry()), newRegistry);
    }

    function test_AddRemoveRequester() public {
        address newRequester = makeAddr("newRequester");

        vm.prank(admin);
        vrfConsumer.addRequester(newRequester);
        assertTrue(vrfConsumer.hasRole(vrfConsumer.REQUESTER_ROLE(), newRequester));

        vm.prank(admin);
        vrfConsumer.removeRequester(newRequester);
        assertFalse(vrfConsumer.hasRole(vrfConsumer.REQUESTER_ROLE(), newRequester));
    }

    function test_PauseUnpause() public {
        vm.prank(admin);
        vrfConsumer.pause();
        assertTrue(vrfConsumer.paused());

        // Should revert when paused
        vm.prank(address(mockGame));
        vm.expectRevert();
        vrfConsumer.requestRandomness(address(mockGame), 1);

        vm.prank(admin);
        vrfConsumer.unpause();
        assertFalse(vrfConsumer.paused());

        // Should work after unpause
        vm.prank(address(mockGame));
        vrfConsumer.requestRandomness(address(mockGame), 1);
    }

    // ============ Fuzz Tests ============

    function testFuzz_RequestMultipleBets(uint8 numBets) public {
        numBets = uint8(bound(numBets, 1, 20));

        for (uint8 i = 0; i < numBets; i++) {
            vm.prank(address(mockGame));
            uint256 requestId = vrfConsumer.requestRandomness(address(mockGame), i + 1);
            assertEq(requestId, i + 1);
        }

        (uint256 requests, , ) = vrfConsumer.getStats();
        assertEq(requests, numBets);
    }
}
