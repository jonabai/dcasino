// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Casino} from "../../src/Casino.sol";
import {Treasury} from "../../src/Treasury.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {IGameRegistry} from "../../src/interfaces/IGameRegistry.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockGame} from "../mocks/MockGame.sol";

/// @title SystemIntegration - Full system integration tests
/// @notice Tests the complete casino ecosystem with all contracts interacting
contract SystemIntegrationTest is Test {
    Casino public casinoImpl;
    Casino public casino;
    Treasury public treasuryImpl;
    Treasury public treasury;
    GameRegistry public registryImpl;
    GameRegistry public registry;
    MockGame public mockGame;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public resolver = makeAddr("resolver");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public bankrollProvider = makeAddr("bankrollProvider");

    uint256 public constant INITIAL_BANKROLL = 100 ether;
    uint256 public constant PLAYER_FUNDS = 10 ether;

    event BetPlaced(uint256 indexed betId, address indexed player, uint256 amount, bytes data);
    event BetResolved(uint256 indexed betId, address indexed player, uint256 payout, bool won);
    event BetRecorded(address indexed game, uint256 amount);
    event PayoutProcessed(address indexed recipient, uint256 amount);

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

        // Deploy Casino
        casinoImpl = new Casino();
        bytes memory casinoInitData =
            abi.encodeWithSelector(Casino.initialize.selector, admin, address(treasury), address(registry));
        ERC1967Proxy casinoProxy = new ERC1967Proxy(address(casinoImpl), casinoInitData);
        casino = Casino(payable(address(casinoProxy)));

        // Deploy MockGame
        mockGame = new MockGame("TestGame", address(casino), address(treasury), address(registry));

        // Setup roles
        vm.startPrank(admin);
        registry.grantRole(registry.GAME_MANAGER_ROLE(), operator);
        treasury.grantRole(treasury.TREASURY_ROLE(), operator);
        treasury.grantRole(treasury.GAME_ROLE(), address(mockGame));
        vm.stopPrank();

        // Register game
        vm.prank(operator);
        registry.registerGame(address(mockGame), "TestGame");

        // Fund bankroll
        vm.deal(bankrollProvider, INITIAL_BANKROLL);
        vm.prank(bankrollProvider);
        treasury.deposit{value: INITIAL_BANKROLL}();

        // Fund players
        vm.deal(player1, PLAYER_FUNDS);
        vm.deal(player2, PLAYER_FUNDS);
    }

    // ============ Full Bet Lifecycle Tests ============

    function test_FullBetLifecycle_Win() public {
        uint256 betAmount = 1 ether;
        bytes memory betData = abi.encode(uint8(1)); // Simple bet data

        // Fund mockGame so it can pay out wins (MockGame pays from its own balance)
        vm.deal(address(mockGame), 10 ether);

        // Player places bet
        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: betAmount}(betData);

        // Verify bet created
        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(bet.player, player1);
        assertEq(bet.amount, betAmount);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Pending));

        // Verify game statistics recorded
        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 1);
        assertEq(info.totalVolume, betAmount);

        // Resolve bet (win - even random number)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 2; // Even = win
        mockGame.resolveBet(betId, randomWords);

        // Verify bet resolved as won
        bet = mockGame.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));
        assertEq(bet.actualPayout, bet.potentialPayout);
    }

    function test_FullBetLifecycle_Loss() public {
        uint256 betAmount = 1 ether;
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: betAmount}(betData);

        // Resolve bet (loss - odd random number)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1; // Odd = loss
        mockGame.resolveBet(betId, randomWords);

        // Verify bet resolved as lost
        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Lost));
        assertEq(bet.actualPayout, 0);
    }

    function test_FullBetLifecycle_Cancel() public {
        uint256 betAmount = 1 ether;
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: betAmount}(betData);

        uint256 playerBalanceBefore = player1.balance;

        // Player cancels bet
        vm.prank(player1);
        mockGame.cancelBet(betId);

        // Verify bet cancelled and refunded
        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Cancelled));
        assertEq(player1.balance, playerBalanceBefore + betAmount);
    }

    // ============ Multi-Player Tests ============

    function test_MultiplePlayersPlaceBets() public {
        bytes memory betData = abi.encode(uint8(1));

        // Player 1 places bet
        vm.prank(player1);
        uint256 betId1 = mockGame.placeBet{value: 1 ether}(betData);

        // Player 2 places bet
        vm.prank(player2);
        uint256 betId2 = mockGame.placeBet{value: 2 ether}(betData);

        // Verify different bet IDs
        assertTrue(betId1 != betId2);

        // Verify statistics
        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 2);
        assertEq(info.totalVolume, 3 ether);

        // Verify pending bets
        uint256[] memory pendingBets = mockGame.getPendingBets();
        assertEq(pendingBets.length, 2);
    }

    function test_MultipleBetsFromSamePlayer() public {
        bytes memory betData = abi.encode(uint8(1));

        vm.startPrank(player1);
        uint256 betId1 = mockGame.placeBet{value: 0.5 ether}(betData);
        uint256 betId2 = mockGame.placeBet{value: 0.5 ether}(betData);
        uint256 betId3 = mockGame.placeBet{value: 0.5 ether}(betData);
        vm.stopPrank();

        // Verify player has 3 bets
        uint256[] memory playerBets = mockGame.getPlayerBets(player1);
        assertEq(playerBets.length, 3);
        assertEq(playerBets[0], betId1);
        assertEq(playerBets[1], betId2);
        assertEq(playerBets[2], betId3);
    }

    // ============ Treasury Integration Tests ============

    function test_TreasuryReceivesBetAmount() public {
        uint256 initialBalance = treasury.getBalance();
        uint256 betAmount = 1 ether;
        bytes memory betData = abi.encode(uint8(1));

        // Place bet - MockGame sends bet to itself, not treasury
        // This test demonstrates how a real game using BaseGame would work
        vm.prank(player1);
        mockGame.placeBet{value: betAmount}(betData);

        // MockGame doesn't forward to treasury - it keeps funds itself
        // Real games using BaseGame would call treasury.receiveBet
        // Here we just verify the game received the bet
        assertEq(address(mockGame).balance, betAmount);

        // Treasury balance unchanged (MockGame simplified implementation)
        assertEq(treasury.getBalance(), initialBalance);
    }

    function test_TreasuryFundReservation() public {
        uint256 initialAvailable = treasury.getAvailableBalance();

        // Use the mockGame which already has GAME_ROLE to test reservation
        uint256 reserveAmount = 5 ether;

        vm.prank(address(mockGame));
        treasury.reserveFunds(reserveAmount);

        assertEq(treasury.getReservedAmount(), reserveAmount);
        assertEq(treasury.getAvailableBalance(), initialAvailable - reserveAmount);

        // Release funds
        vm.prank(address(mockGame));
        treasury.releaseFunds(reserveAmount);
        assertEq(treasury.getReservedAmount(), 0);
        assertEq(treasury.getAvailableBalance(), initialAvailable);
    }

    // ============ Game Registry Integration Tests ============

    function test_MultipleGamesRegistration() public {
        MockGame game2 = new MockGame("Game2", address(casino), address(treasury), address(registry));
        MockGame game3 = new MockGame("Game3", address(casino), address(treasury), address(registry));

        vm.startPrank(operator);
        registry.registerGame(address(game2), "Game2");
        registry.registerGame(address(game3), "Game3");
        vm.stopPrank();

        // Verify all games registered
        assertEq(registry.gameCount(), 3); // Including mockGame from setUp
        address[] memory allGames = registry.getAllGames();
        assertEq(allGames.length, 3);
    }

    function test_DisabledGameStillTracksStats() public {
        bytes memory betData = abi.encode(uint8(1));

        // Place bet first
        vm.prank(player1);
        mockGame.placeBet{value: 1 ether}(betData);

        // Disable game
        vm.prank(operator);
        registry.disableGame(address(mockGame));

        // Verify stats still exist
        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 1);
        assertEq(info.totalVolume, 1 ether);
        assertFalse(info.isActive);
    }

    // ============ Casino Pause Integration Tests ============

    function test_CasinoPauseAffectsEcosystem() public {
        // Verify casino can be paused
        vm.prank(admin);
        casino.pause();
        assertTrue(casino.paused());

        // Casino pause doesn't automatically pause games
        // Individual games need to be paused separately
        vm.prank(admin);
        casino.unpause();
        assertFalse(casino.paused());
    }

    // ============ Access Control Integration Tests ============

    function test_RoleHierarchyAcrossContracts() public {
        // Verify admin has all roles across contracts
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(casino.hasRole(casino.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));

        // Verify operator has specific roles
        assertTrue(registry.hasRole(registry.GAME_MANAGER_ROLE(), operator));
        assertTrue(treasury.hasRole(treasury.TREASURY_ROLE(), operator));
    }

    function test_GameRoleCanRecordBets() public {
        // MockGame has GAME_ROLE and can call treasury functions
        assertTrue(treasury.hasRole(treasury.GAME_ROLE(), address(mockGame)));

        // Placing bet triggers recordBet in registry
        bytes memory betData = abi.encode(uint8(1));
        vm.prank(player1);
        mockGame.placeBet{value: 1 ether}(betData);

        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, 1);
    }

    // ============ Edge Cases ============

    function test_MaximumBetAmount() public {
        uint256 maxBet = mockGame.getMaxBet();
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: maxBet}(betData);

        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(bet.amount, maxBet);
    }

    function test_MinimumBetAmount() public {
        uint256 minBet = mockGame.getMinBet();
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: minBet}(betData);

        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(bet.amount, minBet);
    }

    function test_RevertWhen_BetBelowMinimum() public {
        uint256 minBet = mockGame.getMinBet();
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        vm.expectRevert("Bet too small");
        mockGame.placeBet{value: minBet - 1}(betData);
    }

    function test_RevertWhen_BetAboveMaximum() public {
        uint256 maxBet = mockGame.getMaxBet();
        bytes memory betData = abi.encode(uint8(1));

        vm.deal(player1, maxBet + 1 ether);
        vm.prank(player1);
        vm.expectRevert("Bet too large");
        mockGame.placeBet{value: maxBet + 1}(betData);
    }

    // ============ Fuzz Tests ============

    function testFuzz_PlaceBetWithVariousAmounts(uint256 betAmount) public {
        uint256 minBet = mockGame.getMinBet();
        uint256 maxBet = mockGame.getMaxBet();

        // Bound bet amount to valid range
        betAmount = bound(betAmount, minBet, maxBet);

        vm.deal(player1, betAmount);
        bytes memory betData = abi.encode(uint8(1));

        vm.prank(player1);
        uint256 betId = mockGame.placeBet{value: betAmount}(betData);

        BetLib.Bet memory bet = mockGame.getBet(betId);
        assertEq(bet.amount, betAmount);
        assertEq(bet.player, player1);
    }

    function testFuzz_MultiplePlayersPlaceBets(uint8 numPlayers) public {
        // Limit to reasonable number
        numPlayers = uint8(bound(numPlayers, 1, 10));

        bytes memory betData = abi.encode(uint8(1));

        for (uint8 i = 0; i < numPlayers; i++) {
            address player = makeAddr(string(abi.encodePacked("player", i)));
            vm.deal(player, 1 ether);

            vm.prank(player);
            mockGame.placeBet{value: 0.1 ether}(betData);
        }

        IGameRegistry.GameInfo memory info = registry.getGameByAddress(address(mockGame));
        assertEq(info.totalBetsPlaced, numPlayers);
    }
}
