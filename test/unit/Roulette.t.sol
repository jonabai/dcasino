// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Roulette} from "../../src/games/Roulette.sol";
import {RouletteLib} from "../../src/libraries/RouletteLib.sol";
import {Casino} from "../../src/Casino.sol";
import {Treasury} from "../../src/Treasury.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {VRFConsumer} from "../../src/chainlink/VRFConsumer.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockVRFCoordinator} from "../mocks/MockVRFCoordinator.sol";

contract RouletteTest is Test {
    Roulette public rouletteImpl;
    Roulette public roulette;
    Casino public casinoImpl;
    Casino public casino;
    Treasury public treasuryImpl;
    Treasury public treasury;
    GameRegistry public registryImpl;
    GameRegistry public registry;
    VRFConsumer public vrfConsumerImpl;
    VRFConsumer public vrfConsumer;
    MockVRFCoordinator public vrfCoordinator;

    address public admin = makeAddr("admin");
    address public player = makeAddr("player");
    address public player2 = makeAddr("player2");

    bytes32 public constant KEY_HASH = keccak256("key_hash");
    uint256 public constant SUBSCRIPTION_ID = 1;
    uint32 public constant CALLBACK_GAS_LIMIT = 500000;

    // Events
    event BetPlaced(uint256 indexed betId, address indexed player, uint256 amount, bytes data);
    event BetResolved(uint256 indexed betId, address indexed player, uint256 payout, bool won);
    event WheelSpun(uint256 indexed betId, uint8 winningNumber);
    event BetResult(
        uint256 indexed betId,
        uint8 betIndex,
        RouletteLib.BetType betType,
        uint256 amount,
        uint256 payout,
        bool won
    );

    function setUp() public {
        // Deploy VRF Coordinator mock
        vrfCoordinator = new MockVRFCoordinator();

        // Deploy Treasury
        treasuryImpl = new Treasury();
        bytes memory treasuryInitData = abi.encodeWithSelector(Treasury.initialize.selector, admin);
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImpl), treasuryInitData);
        treasury = Treasury(payable(address(treasuryProxy)));

        // Deploy Casino
        casinoImpl = new Casino();
        bytes memory casinoInitData = abi.encodeWithSelector(Casino.initialize.selector, admin);
        ERC1967Proxy casinoProxy = new ERC1967Proxy(address(casinoImpl), casinoInitData);
        casino = Casino(payable(address(casinoProxy)));

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

        // Deploy Roulette
        rouletteImpl = new Roulette();
        bytes memory rouletteInitData = abi.encodeWithSelector(
            Roulette.initialize.selector,
            admin,
            address(casino),
            address(treasury),
            address(registry),
            address(vrfConsumer)
        );
        ERC1967Proxy rouletteProxy = new ERC1967Proxy(address(rouletteImpl), rouletteInitData);
        roulette = Roulette(address(rouletteProxy));

        // Setup roles and register game
        vm.startPrank(admin);

        // Register game in registry
        registry.registerGame(address(roulette), "European Roulette");

        // Grant GAME_ROLE to roulette on treasury
        treasury.grantRole(treasury.GAME_ROLE(), address(roulette));

        // Add roulette as requester on VRF consumer
        vrfConsumer.addRequester(address(roulette));

        // Grant RESOLVER_ROLE to VRF consumer on roulette
        roulette.grantRole(roulette.RESOLVER_ROLE(), address(vrfConsumer));

        vm.stopPrank();

        // Fund treasury
        vm.deal(admin, 1000 ether);
        vm.prank(admin);
        treasury.deposit{value: 1000 ether}();

        // Fund players
        vm.deal(player, 100 ether);
        vm.deal(player2, 100 ether);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(roulette.gameName(), "European Roulette");
        assertTrue(roulette.hasRole(roulette.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(roulette.hasRole(roulette.UPGRADER_ROLE(), admin));
        assertEq(roulette.getHouseEdge(), RouletteLib.HOUSE_EDGE);
    }

    function test_RevertWhen_InitializeZeroAdmin() public {
        Roulette newImpl = new Roulette();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                Roulette.initialize.selector,
                address(0),
                address(casino),
                address(treasury),
                address(registry),
                address(vrfConsumer)
            )
        );
    }

    // ============ Straight Bet Tests ============

    function test_PlaceStraightBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        assertEq(betId, 1);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(bet.player, player);
        assertEq(bet.amount, 1 ether);
        // Straight bet pays 35:1, so payout = bet + (bet * 35) = 36 ether
        assertEq(bet.potentialPayout, 36 ether);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Pending));
    }

    function test_PlaceStraightBetOnZero() public {
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(0);

        assertEq(betId, 1);
        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(bets.length, 1);
        assertEq(bets[0].numbers[0], 0);
    }

    function test_RevertWhen_StraightBetInvalidNumber() public {
        vm.prank(player);
        vm.expectRevert(Roulette.InvalidBetNumbers.selector);
        roulette.placeStraightBet{value: 1 ether}(37);
    }

    // ============ Split Bet Tests ============

    function test_PlaceSplitBetHorizontal() public {
        // 1 and 2 are horizontally adjacent
        vm.prank(player);
        uint256 betId = roulette.placeSplitBet{value: 1 ether}(1, 2);

        assertEq(betId, 1);
        BetLib.Bet memory bet = roulette.getBet(betId);
        // Split pays 17:1, so payout = bet + (bet * 17) = 18 ether
        assertEq(bet.potentialPayout, 18 ether);
    }

    function test_PlaceSplitBetVertical() public {
        // 1 and 4 are vertically adjacent
        vm.prank(player);
        uint256 betId = roulette.placeSplitBet{value: 1 ether}(1, 4);

        assertEq(betId, 1);
    }

    function test_PlaceSplitBetWithZero() public {
        // 0 can split with 1, 2, or 3
        vm.prank(player);
        uint256 betId = roulette.placeSplitBet{value: 1 ether}(0, 2);

        assertEq(betId, 1);
    }

    function test_RevertWhen_SplitBetNonAdjacent() public {
        vm.prank(player);
        vm.expectRevert(Roulette.InvalidBetNumbers.selector);
        roulette.placeSplitBet{value: 1 ether}(1, 5);
    }

    // ============ Even Money Bet Tests ============

    function test_PlaceRedBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeRedBet{value: 1 ether}();

        BetLib.Bet memory bet = roulette.getBet(betId);
        // Even money pays 1:1, so payout = bet + bet = 2 ether
        assertEq(bet.potentialPayout, 2 ether);

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(bets.length, 1);
        assertEq(uint8(bets[0].betType), uint8(RouletteLib.BetType.Red));
        assertEq(bets[0].numbers.length, 18);
    }

    function test_PlaceBlackBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeBlackBet{value: 1 ether}();

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(bet.potentialPayout, 2 ether);
    }

    function test_PlaceOddBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeOddBet{value: 1 ether}();

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(uint8(bets[0].betType), uint8(RouletteLib.BetType.Odd));
    }

    function test_PlaceEvenBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeEvenBet{value: 1 ether}();

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(uint8(bets[0].betType), uint8(RouletteLib.BetType.Even));
    }

    function test_PlaceLowBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeLowBet{value: 1 ether}();

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(uint8(bets[0].betType), uint8(RouletteLib.BetType.Low));
        // Check first and last numbers
        assertEq(bets[0].numbers[0], 1);
        assertEq(bets[0].numbers[17], 18);
    }

    function test_PlaceHighBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeHighBet{value: 1 ether}();

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(uint8(bets[0].betType), uint8(RouletteLib.BetType.High));
        // Check first and last numbers
        assertEq(bets[0].numbers[0], 19);
        assertEq(bets[0].numbers[17], 36);
    }

    // ============ Column and Dozen Bet Tests ============

    function test_PlaceColumnBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeColumnBet{value: 1 ether}(1);

        BetLib.Bet memory bet = roulette.getBet(betId);
        // Column pays 2:1, so payout = bet + (bet * 2) = 3 ether
        assertEq(bet.potentialPayout, 3 ether);

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(bets[0].numbers.length, 12);
        // Column 1: 1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34
        assertEq(bets[0].numbers[0], 1);
        assertEq(bets[0].numbers[1], 4);
    }

    function test_PlaceDozenBet() public {
        vm.prank(player);
        uint256 betId = roulette.placeDozenBet{value: 1 ether}(2);

        BetLib.Bet memory bet = roulette.getBet(betId);
        // Dozen pays 2:1
        assertEq(bet.potentialPayout, 3 ether);

        RouletteLib.RouletteBet[] memory bets = roulette.getRouletteBets(betId);
        assertEq(bets[0].numbers.length, 12);
        // Dozen 2: 13-24
        assertEq(bets[0].numbers[0], 13);
        assertEq(bets[0].numbers[11], 24);
    }

    // ============ Bet Resolution Tests ============

    function test_ResolveStraightBetWin() public {
        // Place a straight bet on 17
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill VRF with number that results in 17
        // winningNumber = randomWord % 37 = 17
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 17; // 17 % 37 = 17

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        // Verify bet resolved as win
        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));
        assertEq(roulette.getWinningNumber(betId), 17);

        // Player should receive 36 ether payout
        assertEq(player.balance, playerBalanceBefore + 36 ether);
    }

    function test_ResolveStraightBetLose() public {
        // Place a straight bet on 17
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill VRF with number that results in different number
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0; // 0 % 37 = 0

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        // Verify bet resolved as loss
        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Lost));
        assertEq(roulette.getWinningNumber(betId), 0);

        // Player balance unchanged (already lost bet amount)
        assertEq(player.balance, playerBalanceBefore);
    }

    function test_ResolveRedBetWin() public {
        // Place a red bet
        vm.prank(player);
        uint256 betId = roulette.placeRedBet{value: 1 ether}();

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with red number (1 is red)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1; // 1 % 37 = 1 (red)

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));

        // Player should receive 2 ether payout (1:1)
        assertEq(player.balance, playerBalanceBefore + 2 ether);
    }

    function test_ResolveRedBetLoseOnZero() public {
        // Place a red bet
        vm.prank(player);
        uint256 betId = roulette.placeRedBet{value: 1 ether}();

        // Fulfill with 0 (neither red nor black - house wins)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 0;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Lost));
    }

    function test_ResolveBlackBetWin() public {
        // Place a black bet
        vm.prank(player);
        uint256 betId = roulette.placeBlackBet{value: 1 ether}();

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with black number (2 is black)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 2; // 2 % 37 = 2 (black)

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));
        assertEq(player.balance, playerBalanceBefore + 2 ether);
    }

    function test_ResolveSplitBetWin() public {
        // Place a split bet on 1 and 2
        vm.prank(player);
        uint256 betId = roulette.placeSplitBet{value: 1 ether}(1, 2);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with number 2
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 2;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));

        // Split pays 17:1, so payout = 18 ether
        assertEq(player.balance, playerBalanceBefore + 18 ether);
    }

    function test_ResolveColumnBetWin() public {
        // Place a column 1 bet (1, 4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34)
        vm.prank(player);
        uint256 betId = roulette.placeColumnBet{value: 1 ether}(1);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with number 7 (in column 1)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 7;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));

        // Column pays 2:1, so payout = 3 ether
        assertEq(player.balance, playerBalanceBefore + 3 ether);
    }

    function test_ResolveDozenBetWin() public {
        // Place a dozen 1 bet (1-12)
        vm.prank(player);
        uint256 betId = roulette.placeDozenBet{value: 1 ether}(1);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with number 5 (in first dozen)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 5;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won));

        // Dozen pays 2:1, so payout = 3 ether
        assertEq(player.balance, playerBalanceBefore + 3 ether);
    }

    // ============ Complex Bet Tests (Multiple Bets) ============

    function test_PlaceMultipleBetsViaPlaceBet() public {
        // Create array of bets
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](2);

        // Bet 1: Straight on 17
        uint8[] memory numbers1 = new uint8[](1);
        numbers1[0] = 17;
        bets[0] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Straight,
            numbers: numbers1,
            amount: 0.5 ether
        });

        // Bet 2: Red
        bets[1] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Red,
            numbers: RouletteLib.getRedNumbers(),
            amount: 0.5 ether
        });

        bytes memory betData = abi.encode(bets);

        vm.prank(player);
        uint256 betId = roulette.placeBet{value: 1 ether}(betData);

        RouletteLib.RouletteBet[] memory storedBets = roulette.getRouletteBets(betId);
        assertEq(storedBets.length, 2);
    }

    function test_ResolveMultipleBetsPartialWin() public {
        // Create array of bets
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](2);

        // Bet 1: Straight on 17 (will lose)
        uint8[] memory numbers1 = new uint8[](1);
        numbers1[0] = 17;
        bets[0] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Straight,
            numbers: numbers1,
            amount: 0.5 ether
        });

        // Bet 2: Red (will win, since 1 is red)
        bets[1] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Red,
            numbers: RouletteLib.getRedNumbers(),
            amount: 0.5 ether
        });

        bytes memory betData = abi.encode(bets);

        vm.prank(player);
        uint256 betId = roulette.placeBet{value: 1 ether}(betData);

        uint256 playerBalanceBefore = player.balance;

        // Fulfill with 1 (red, not 17)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Won)); // anyWin = true

        // Only red bet wins: 0.5 * 2 = 1 ether
        assertEq(player.balance, playerBalanceBefore + 1 ether);
    }

    // ============ Error Cases ============

    function test_RevertWhen_NoBets() public {
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](0);
        bytes memory betData = abi.encode(bets);

        vm.prank(player);
        vm.expectRevert(Roulette.NoBets.selector);
        roulette.placeBet{value: 1 ether}(betData);
    }

    function test_RevertWhen_TooManyBets() public {
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](21);
        uint8[] memory numbers = new uint8[](1);
        numbers[0] = 17;

        for (uint8 i = 0; i < 21; i++) {
            bets[i] = RouletteLib.RouletteBet({
                betType: RouletteLib.BetType.Straight,
                numbers: numbers,
                amount: 0.1 ether
            });
        }

        bytes memory betData = abi.encode(bets);

        vm.prank(player);
        vm.expectRevert(Roulette.TooManyBets.selector);
        roulette.placeBet{value: 2.1 ether}(betData);
    }

    function test_RevertWhen_AmountMismatch() public {
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](1);
        uint8[] memory numbers = new uint8[](1);
        numbers[0] = 17;
        bets[0] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Straight,
            numbers: numbers,
            amount: 1 ether
        });

        bytes memory betData = abi.encode(bets);

        vm.prank(player);
        vm.expectRevert(Errors.InvalidAmount.selector);
        roulette.placeBet{value: 0.5 ether}(betData); // Sending less than bet amount
    }

    function test_RevertWhen_BelowMinBet() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Errors.BetTooSmall.selector, 0.0001 ether, 0.001 ether));
        roulette.placeStraightBet{value: 0.0001 ether}(17);
    }

    function test_RevertWhen_AboveMaxBet() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Errors.BetTooLarge.selector, 100 ether, 10 ether));
        roulette.placeStraightBet{value: 100 ether}(17);
    }

    function test_RevertWhen_InsufficientTreasury() public {
        // Drain treasury
        vm.prank(admin);
        treasury.withdraw(990 ether);

        // Try to place a bet with high payout
        vm.prank(player);
        vm.expectRevert(Errors.InsufficientTreasuryBalance.selector);
        roulette.placeStraightBet{value: 1 ether}(17); // Would need 36 ether payout
    }

    function test_RevertWhen_Paused() public {
        vm.prank(admin);
        roulette.pause();

        vm.prank(player);
        vm.expectRevert();
        roulette.placeStraightBet{value: 1 ether}(17);
    }

    // ============ View Function Tests ============

    function test_CalculateBetPayout() public view {
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](2);

        uint8[] memory numbers1 = new uint8[](1);
        numbers1[0] = 17;
        bets[0] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Straight,
            numbers: numbers1,
            amount: 1 ether
        });

        bets[1] = RouletteLib.RouletteBet({
            betType: RouletteLib.BetType.Red,
            numbers: RouletteLib.getRedNumbers(),
            amount: 1 ether
        });

        bytes memory betData = abi.encode(bets);
        uint256 maxPayout = roulette.calculateBetPayout(betData);

        // Straight: 1 * 36 = 36 ether
        // Red: 1 * 2 = 2 ether
        // Total max: 38 ether
        assertEq(maxPayout, 38 ether);
    }

    function test_GetHouseEdge() public view {
        assertEq(roulette.getHouseEdge(), 270); // 2.7%
    }

    // ============ Fuzz Tests ============

    function testFuzz_StraightBetValidNumber(uint8 number) public {
        number = uint8(bound(number, 0, 36));

        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(number);

        assertGt(betId, 0);
    }

    function testFuzz_StraightBetInvalidNumber(uint8 number) public {
        vm.assume(number > 36);

        vm.prank(player);
        vm.expectRevert(Roulette.InvalidBetNumbers.selector);
        roulette.placeStraightBet{value: 1 ether}(number);
    }

    function testFuzz_BetAmount(uint256 amount) public {
        // Constrain amount so that potential payout (36x for straight) doesn't exceed treasury's max payout
        // Treasury has 1000 ETH, max payout is 5% = 50 ETH
        // So max bet for straight is 50/36 = ~1.38 ETH
        amount = bound(amount, 0.001 ether, 1.3 ether);

        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: amount}(17);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(bet.amount, amount);
        assertEq(bet.potentialPayout, amount * 36);
    }

    function testFuzz_WinningNumber(uint256 randomWord) public {
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomWord;

        vrfCoordinator.fulfillRandomWords(1, randomWords);

        uint8 winningNumber = roulette.getWinningNumber(betId);
        assertLe(winningNumber, 36);
        assertEq(winningNumber, uint8(randomWord % 37));
    }

    // ============ Multiple Player Tests ============

    function test_MultiplePlayers() public {
        // Player 1 places bet
        vm.prank(player);
        uint256 betId1 = roulette.placeStraightBet{value: 1 ether}(17);

        // Player 2 places bet
        vm.prank(player2);
        uint256 betId2 = roulette.placeRedBet{value: 1 ether}();

        assertEq(betId1, 1);
        assertEq(betId2, 2);

        // Check bets are independent
        BetLib.Bet memory bet1 = roulette.getBet(betId1);
        BetLib.Bet memory bet2 = roulette.getBet(betId2);

        assertEq(bet1.player, player);
        assertEq(bet2.player, player2);
    }

    // ============ Cancel Bet Tests ============

    function test_CancelBetByPlayer() public {
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        uint256 playerBalanceBefore = player.balance;

        // Player cancels their own bet
        vm.prank(player);
        roulette.cancelBet(betId);

        BetLib.Bet memory bet = roulette.getBet(betId);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Cancelled));

        // Player should be refunded
        assertEq(player.balance, playerBalanceBefore + 1 ether);
    }

    function test_RevertWhen_CancelBetByNonPlayer() public {
        vm.prank(player);
        uint256 betId = roulette.placeStraightBet{value: 1 ether}(17);

        // Admin tries to cancel - should fail
        vm.prank(admin);
        vm.expectRevert(Errors.Unauthorized.selector);
        roulette.cancelBet(betId);
    }
}
