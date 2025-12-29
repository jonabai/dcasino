// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {Treasury} from "../../src/Treasury.sol";
import {IGameRegistry} from "../../src/interfaces/IGameRegistry.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockGame} from "../mocks/MockGame.sol";

contract GameRegistryTest is Test {
    GameRegistry public registryImpl;
    GameRegistry public registry;
    Treasury public treasuryImpl;
    Treasury public treasury;
    MockGame public mockGame;

    address public admin = makeAddr("admin");
    address public gameManager = makeAddr("gameManager");
    address public randomUser = makeAddr("randomUser");

    event GameRegistered(address indexed game, bytes32 indexed gameId, string name);
    event GameDeregistered(address indexed game, bytes32 indexed gameId);
    event GameEnabled(address indexed game);
    event GameDisabled(address indexed game);
    event BetRecorded(address indexed game, uint256 amount);

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

        // Deploy MockGame
        mockGame = new MockGame("TestGame", address(0), address(treasury), address(registry));

        // Setup roles
        vm.startPrank(admin);
        registry.grantRole(registry.GAME_MANAGER_ROLE(), gameManager);
        vm.stopPrank();

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(address(mockGame), 100 ether);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.GAME_MANAGER_ROLE(), admin));
        assertTrue(registry.hasRole(registry.UPGRADER_ROLE(), admin));
        assertEq(address(registry.treasury()), address(treasury));
    }

    function test_RevertWhen_InitializeWithZeroAdmin() public {
        GameRegistry newImpl = new GameRegistry();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl), abi.encodeWithSelector(GameRegistry.initialize.selector, address(0), address(treasury))
        );
    }

    function test_RevertWhen_InitializeWithZeroTreasury() public {
        GameRegistry newImpl = new GameRegistry();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl), abi.encodeWithSelector(GameRegistry.initialize.selector, admin, address(0))
        );
    }

    // ============ Register Game Tests ============

    function test_RegisterGame() public {
        vm.prank(gameManager);
        vm.expectEmit(true, false, false, true);
        emit GameRegistered(address(mockGame), bytes32(0), "TestGame"); // gameId is dynamic
        bytes32 gameId = registry.registerGame(address(mockGame), "TestGame");

        assertTrue(registry.isRegisteredGame(address(mockGame)));
        assertTrue(registry.isActiveGame(address(mockGame)));
        assertEq(registry.gameCount(), 1);

        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.gameAddress, address(mockGame));
        assertEq(info.gameId, gameId);
        assertEq(info.name, "TestGame");
        assertTrue(info.isActive);
        assertEq(info.totalBetsPlaced, 0);
        assertEq(info.totalVolume, 0);
    }

    function test_RevertWhen_RegisterGameWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        registry.registerGame(address(mockGame), "TestGame");
    }

    function test_RevertWhen_RegisterZeroAddress() public {
        vm.prank(gameManager);
        vm.expectRevert(Errors.InvalidGameAddress.selector);
        registry.registerGame(address(0), "TestGame");
    }

    function test_RevertWhen_RegisterGameTwice() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(gameManager);
        vm.expectRevert(Errors.GameAlreadyRegistered.selector);
        registry.registerGame(address(mockGame), "TestGame");
    }

    function test_RevertWhen_RegisterNonGame() public {
        vm.prank(gameManager);
        vm.expectRevert(Errors.GameDoesNotImplementInterface.selector);
        registry.registerGame(address(treasury), "NotAGame");
    }

    // ============ Deregister Game Tests ============

    function test_DeregisterGame() public {
        vm.prank(gameManager);
        bytes32 gameId = registry.registerGame(address(mockGame), "TestGame");

        vm.prank(gameManager);
        vm.expectEmit(true, true, false, false);
        emit GameDeregistered(address(mockGame), gameId);
        registry.deregisterGame(address(mockGame));

        assertFalse(registry.isRegisteredGame(address(mockGame)));
        assertEq(registry.gameCount(), 0);
    }

    function test_RevertWhen_DeregisterUnregisteredGame() public {
        vm.prank(gameManager);
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.deregisterGame(address(mockGame));
    }

    function test_RevertWhen_DeregisterWithoutRole() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(randomUser);
        vm.expectRevert();
        registry.deregisterGame(address(mockGame));
    }

    // ============ Enable/Disable Game Tests ============

    function test_DisableGame() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(gameManager);
        vm.expectEmit(true, false, false, false);
        emit GameDisabled(address(mockGame));
        registry.disableGame(address(mockGame));

        assertFalse(registry.isActiveGame(address(mockGame)));
        assertTrue(registry.isRegisteredGame(address(mockGame)));
    }

    function test_EnableGame() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(gameManager);
        registry.disableGame(address(mockGame));

        vm.prank(gameManager);
        vm.expectEmit(true, false, false, false);
        emit GameEnabled(address(mockGame));
        registry.enableGame(address(mockGame));

        assertTrue(registry.isActiveGame(address(mockGame)));
    }

    function test_DisableAlreadyDisabledGame() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(gameManager);
        registry.disableGame(address(mockGame));

        // Should not emit event or revert
        vm.prank(gameManager);
        registry.disableGame(address(mockGame));

        assertFalse(registry.isActiveGame(address(mockGame)));
    }

    function test_EnableAlreadyEnabledGame() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        // Should not emit event or revert
        vm.prank(gameManager);
        registry.enableGame(address(mockGame));

        assertTrue(registry.isActiveGame(address(mockGame)));
    }

    function test_RevertWhen_DisableUnregisteredGame() public {
        vm.prank(gameManager);
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.disableGame(address(mockGame));
    }

    function test_RevertWhen_EnableUnregisteredGame() public {
        vm.prank(gameManager);
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.enableGame(address(mockGame));
    }

    // ============ Record Bet Tests ============

    function test_RecordBet() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        uint256 betAmount = 1 ether;

        vm.prank(address(mockGame));
        vm.expectEmit(true, false, false, true);
        emit BetRecorded(address(mockGame), betAmount);
        registry.recordBet(address(mockGame), betAmount);

        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 1);
        assertEq(info.totalVolume, betAmount);
    }

    function test_RecordMultipleBets() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(address(mockGame));
        registry.recordBet(address(mockGame), 1 ether);

        vm.prank(address(mockGame));
        registry.recordBet(address(mockGame), 2 ether);

        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 2);
        assertEq(info.totalVolume, 3 ether);
    }

    function test_RevertWhen_RecordBetUnregisteredGame() public {
        vm.prank(address(mockGame));
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.recordBet(address(mockGame), 1 ether);
    }

    function test_RevertWhen_RecordBetNotFromGame() public {
        vm.prank(gameManager);
        registry.registerGame(address(mockGame), "TestGame");

        vm.prank(randomUser);
        vm.expectRevert(Errors.Unauthorized.selector);
        registry.recordBet(address(mockGame), 1 ether);
    }

    // ============ View Function Tests ============

    function test_GetAllGames() public {
        MockGame game1 = new MockGame("Game1", address(0), address(treasury), address(registry));
        MockGame game2 = new MockGame("Game2", address(0), address(treasury), address(registry));

        vm.startPrank(gameManager);
        registry.registerGame(address(game1), "Game1");
        registry.registerGame(address(game2), "Game2");
        vm.stopPrank();

        address[] memory games = registry.getAllGames();
        assertEq(games.length, 2);
    }

    function test_GetActiveGames() public {
        MockGame game1 = new MockGame("Game1", address(0), address(treasury), address(registry));
        MockGame game2 = new MockGame("Game2", address(0), address(treasury), address(registry));

        vm.startPrank(gameManager);
        registry.registerGame(address(game1), "Game1");
        registry.registerGame(address(game2), "Game2");
        registry.disableGame(address(game1));
        vm.stopPrank();

        address[] memory activeGames = registry.getActiveGames();
        assertEq(activeGames.length, 1);
        assertEq(activeGames[0], address(game2));
    }

    function test_GetGameById() public {
        vm.prank(gameManager);
        bytes32 gameId = registry.registerGame(address(mockGame), "TestGame");

        IGameRegistry.GameInfo memory info = registry.getGame(gameId);
        assertEq(info.gameAddress, address(mockGame));
        assertEq(info.name, "TestGame");
    }

    function test_RevertWhen_GetGameByInvalidId() public {
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.getGame(bytes32(0));
    }

    function test_GetGameId() public {
        vm.prank(gameManager);
        bytes32 expectedId = registry.registerGame(address(mockGame), "TestGame");

        bytes32 actualId = registry.getGameId(address(mockGame));
        assertEq(actualId, expectedId);
    }

    function test_RevertWhen_GetGameIdUnregistered() public {
        vm.expectRevert(Errors.GameNotRegistered.selector);
        registry.getGameId(address(mockGame));
    }

    // ============ Set Treasury Tests ============

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        registry.setTreasury(newTreasury);

        assertEq(address(registry.treasury()), newTreasury);
    }

    function test_RevertWhen_SetTreasuryZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        registry.setTreasury(address(0));
    }

    function test_RevertWhen_SetTreasuryWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        registry.setTreasury(makeAddr("newTreasury"));
    }
}
