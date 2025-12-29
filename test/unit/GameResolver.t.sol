// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameResolver} from "../../src/chainlink/GameResolver.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {Treasury} from "../../src/Treasury.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockGame} from "../mocks/MockGame.sol";

contract GameResolverTest is Test {
    GameResolver public resolverImpl;
    GameResolver public resolver;
    GameRegistry public registryImpl;
    GameRegistry public registry;
    Treasury public treasuryImpl;
    Treasury public treasury;
    MockGame public mockGame;

    address public admin = makeAddr("admin");
    address public forwarder = makeAddr("forwarder");
    address public player = makeAddr("player");

    uint256 public constant RESOLUTION_DELAY = 60; // 60 seconds
    uint256 public constant MAX_PENDING_TIME = 3600; // 1 hour

    event AutomationEnabled(address indexed game);
    event AutomationDisabled(address indexed game);
    event UpkeepPerformed(address indexed game, uint256[] betIds, uint256 timestamp);

    function setUp() public {
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

        // Deploy GameResolver
        resolverImpl = new GameResolver();
        bytes memory resolverInitData = abi.encodeWithSelector(
            GameResolver.initialize.selector, admin, address(registry), RESOLUTION_DELAY, MAX_PENDING_TIME
        );
        ERC1967Proxy resolverProxy = new ERC1967Proxy(address(resolverImpl), resolverInitData);
        resolver = GameResolver(address(resolverProxy));

        // Deploy MockGame
        mockGame = new MockGame("TestGame", address(0), address(treasury), address(registry));

        // Setup: Register game and enable automation
        vm.startPrank(admin);
        registry.registerGame(address(mockGame), "TestGame");
        resolver.enableAutomation(address(mockGame));
        resolver.setForwarder(forwarder);
        vm.stopPrank();

        // Fund accounts
        vm.deal(player, 10 ether);
        vm.deal(address(mockGame), 100 ether); // For payouts
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertTrue(resolver.hasRole(resolver.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(resolver.hasRole(resolver.UPGRADER_ROLE(), admin));
        assertEq(address(resolver.gameRegistry()), address(registry));
        assertEq(resolver.minResolutionDelay(), RESOLUTION_DELAY);
        assertEq(resolver.maxPendingTime(), MAX_PENDING_TIME);
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        GameResolver newImpl = new GameResolver();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                GameResolver.initialize.selector,
                address(0),
                address(registry),
                RESOLUTION_DELAY,
                MAX_PENDING_TIME
            )
        );
    }

    // ============ Automation Enable/Disable Tests ============

    function test_EnableAutomation() public {
        MockGame newGame = new MockGame("NewGame", address(0), address(treasury), address(registry));

        vm.prank(admin);
        registry.registerGame(address(newGame), "NewGame");

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit AutomationEnabled(address(newGame));
        resolver.enableAutomation(address(newGame));

        assertTrue(resolver.automationEnabled(address(newGame)));
    }

    function test_DisableAutomation() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit AutomationDisabled(address(mockGame));
        resolver.disableAutomation(address(mockGame));

        assertFalse(resolver.automationEnabled(address(mockGame)));
    }

    function test_RevertWhen_EnableAutomationUnregisteredGame() public {
        address unregistered = makeAddr("unregistered");

        vm.prank(admin);
        vm.expectRevert(Errors.GameNotRegistered.selector);
        resolver.enableAutomation(unregistered);
    }

    function test_GetAutomatedGames() public {
        MockGame game2 = new MockGame("Game2", address(0), address(treasury), address(registry));

        vm.startPrank(admin);
        registry.registerGame(address(game2), "Game2");
        resolver.enableAutomation(address(game2));
        vm.stopPrank();

        address[] memory games = resolver.getAutomatedGames();
        assertEq(games.length, 2);
    }

    // ============ Check Upkeep Tests ============

    function test_CheckUpkeepNoPendingBets() public view {
        (bool upkeepNeeded, bytes memory performData) = resolver.checkUpkeep("");

        assertFalse(upkeepNeeded);
        assertEq(performData.length, 0);
    }

    function test_CheckUpkeepWithEligibleBet() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Move time past resolution delay
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);

        (bool upkeepNeeded, bytes memory performData) = resolver.checkUpkeep("");

        assertTrue(upkeepNeeded);
        assertTrue(performData.length > 0);

        // Decode and verify
        (address game, uint256[] memory betIds) = abi.decode(performData, (address, uint256[]));
        assertEq(game, address(mockGame));
        assertEq(betIds.length, 1);
        assertEq(betIds[0], 1);
    }

    function test_CheckUpkeepBetTooEarly() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Don't move time - bet is too early
        (bool upkeepNeeded, ) = resolver.checkUpkeep("");

        assertFalse(upkeepNeeded);
    }

    function test_CheckUpkeepBetTooOld() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Move time past max pending time
        vm.warp(block.timestamp + MAX_PENDING_TIME + 1);

        (bool upkeepNeeded, ) = resolver.checkUpkeep("");

        assertFalse(upkeepNeeded); // Stale bet is not eligible
    }

    function test_CheckUpkeepWhenPaused() public {
        vm.prank(admin);
        resolver.pause();

        (bool upkeepNeeded, ) = resolver.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    // ============ Perform Upkeep Tests ============

    function test_PerformUpkeep() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Move time past resolution delay
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);

        // Check upkeep
        (bool upkeepNeeded, bytes memory performData) = resolver.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Perform upkeep
        vm.prank(forwarder);
        resolver.performUpkeep(performData);

        // Stats should be updated
        (uint256 upkeeps, uint256 resolved, ) = resolver.getStats();
        assertEq(upkeeps, 1);
        assertGt(resolved, 0);
    }

    function test_RevertWhen_PerformUpkeepUnauthorized() public {
        bytes memory performData = abi.encode(address(mockGame), new uint256[](0));

        vm.prank(player);
        vm.expectRevert(Errors.Unauthorized.selector);
        resolver.performUpkeep(performData);
    }

    function test_ManualUpkeep() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        uint256[] memory betIds = new uint256[](1);
        betIds[0] = 1;

        vm.prank(admin);
        resolver.manualUpkeep(address(mockGame), betIds);

        (uint256 upkeeps, , ) = resolver.getStats();
        assertEq(upkeeps, 1);
    }

    // ============ Admin Function Tests ============

    function test_SetResolutionDelay() public {
        uint256 newDelay = 120;

        vm.prank(admin);
        resolver.setResolutionDelay(newDelay);

        assertEq(resolver.minResolutionDelay(), newDelay);
    }

    function test_SetMaxPendingTime() public {
        uint256 newTime = 7200;

        vm.prank(admin);
        resolver.setMaxPendingTime(newTime);

        assertEq(resolver.maxPendingTime(), newTime);
    }

    function test_SetGameRegistry() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(admin);
        resolver.setGameRegistry(newRegistry);

        assertEq(address(resolver.gameRegistry()), newRegistry);
    }

    function test_SetForwarder() public {
        address newForwarder = makeAddr("newForwarder");

        vm.prank(admin);
        resolver.setForwarder(newForwarder);

        assertTrue(resolver.hasRole(resolver.FORWARDER_ROLE(), newForwarder));
    }

    function test_RemoveForwarder() public {
        vm.prank(admin);
        resolver.removeForwarder(forwarder);

        assertFalse(resolver.hasRole(resolver.FORWARDER_ROLE(), forwarder));
    }

    function test_PauseUnpause() public {
        vm.prank(admin);
        resolver.pause();
        assertTrue(resolver.paused());

        vm.prank(admin);
        resolver.unpause();
        assertFalse(resolver.paused());
    }

    // ============ Edge Case Tests ============

    function test_IsEligibleForResolution() public {
        // Player places bet
        vm.prank(player);
        mockGame.placeBet{value: 1 ether}(abi.encode(uint8(1)));

        // Too early
        assertFalse(resolver.isEligibleForResolution(address(mockGame), 1));

        // After delay
        vm.warp(block.timestamp + RESOLUTION_DELAY + 1);
        assertTrue(resolver.isEligibleForResolution(address(mockGame), 1));

        // After max time
        vm.warp(block.timestamp + MAX_PENDING_TIME + 1);
        assertFalse(resolver.isEligibleForResolution(address(mockGame), 1));
    }

    function test_DisableAutomationRemovesFromArray() public {
        // Add second game
        MockGame game2 = new MockGame("Game2", address(0), address(treasury), address(registry));

        vm.startPrank(admin);
        registry.registerGame(address(game2), "Game2");
        resolver.enableAutomation(address(game2));
        vm.stopPrank();

        // Verify both are present
        address[] memory games = resolver.getAutomatedGames();
        assertEq(games.length, 2);

        // Disable first game
        vm.prank(admin);
        resolver.disableAutomation(address(mockGame));

        // Verify removal
        games = resolver.getAutomatedGames();
        assertEq(games.length, 1);
        assertEq(games[0], address(game2));
    }

    // ============ Stats Tests ============

    function test_GetStats() public {
        address[] memory games = resolver.getAutomatedGames();
        (uint256 upkeeps, uint256 resolved, uint256 numGames) = resolver.getStats();

        assertEq(upkeeps, 0);
        assertEq(resolved, 0);
        assertEq(numGames, games.length);
    }
}
