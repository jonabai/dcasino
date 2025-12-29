// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Blackjack} from "../../src/games/Blackjack.sol";
import {BlackjackLib} from "../../src/libraries/BlackjackLib.sol";
import {Casino} from "../../src/Casino.sol";
import {Treasury} from "../../src/Treasury.sol";
import {GameRegistry} from "../../src/GameRegistry.sol";
import {VRFConsumer} from "../../src/chainlink/VRFConsumer.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockVRFCoordinator} from "../mocks/MockVRFCoordinator.sol";

contract BlackjackTest is Test {
    Blackjack public blackjackImpl;
    Blackjack public blackjack;
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
    uint32 public constant CALLBACK_GAS_LIMIT = 2000000;  // Higher for blackjack

    // Card IDs for testing (card = suit * 13 + rank)
    // Ace of Hearts = 0, 2 of Hearts = 1, ..., K of Hearts = 12
    // Ace of Diamonds = 13, etc.
    uint8 constant ACE_HEARTS = 0;
    uint8 constant TWO_HEARTS = 1;
    uint8 constant THREE_HEARTS = 2;
    uint8 constant FOUR_HEARTS = 3;
    uint8 constant FIVE_HEARTS = 4;
    uint8 constant SIX_HEARTS = 5;
    uint8 constant SEVEN_HEARTS = 6;
    uint8 constant EIGHT_HEARTS = 7;
    uint8 constant NINE_HEARTS = 8;
    uint8 constant TEN_HEARTS = 9;
    uint8 constant JACK_HEARTS = 10;
    uint8 constant QUEEN_HEARTS = 11;
    uint8 constant KING_HEARTS = 12;
    uint8 constant ACE_DIAMONDS = 13;
    uint8 constant FIVE_DIAMONDS = 17;
    uint8 constant SIX_DIAMONDS = 18;
    uint8 constant TEN_DIAMONDS = 22;
    uint8 constant KING_DIAMONDS = 25;
    uint8 constant ACE_CLUBS = 26;
    uint8 constant TEN_CLUBS = 35;
    uint8 constant ACE_SPADES = 39;
    uint8 constant TEN_SPADES = 48;

    // Events
    event BetPlaced(uint256 indexed betId, address indexed player, uint256 amount, bytes data);
    event GameStarted(uint256 indexed betId, uint8 playerCard1, uint8 playerCard2, uint8 dealerUpCard);
    event CardDealt(uint256 indexed betId, uint8 handIndex, uint8 cardId, bool isPlayer);
    event PlayerAction(uint256 indexed betId, uint8 handIndex, BlackjackLib.Action action);
    event DealerRevealed(uint256 indexed betId, uint8 holeCard);
    event HandResolved(uint256 indexed betId, uint8 handIndex, BlackjackLib.Outcome outcome, uint256 payout);
    event BetResolved(uint256 indexed betId, address indexed player, uint256 payout, bool won);

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

        // Deploy VRFConsumer with higher numWords for blackjack
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

        // Configure VRF for more random words
        vm.prank(admin);
        vrfConsumer.setVRFConfig(KEY_HASH, SUBSCRIPTION_ID, 3, CALLBACK_GAS_LIMIT, 10, false);

        // Deploy Blackjack
        blackjackImpl = new Blackjack();
        bytes memory blackjackInitData = abi.encodeWithSelector(
            Blackjack.initialize.selector,
            admin,
            address(casino),
            address(treasury),
            address(registry),
            address(vrfConsumer)
        );
        ERC1967Proxy blackjackProxy = new ERC1967Proxy(address(blackjackImpl), blackjackInitData);
        blackjack = Blackjack(address(blackjackProxy));

        // Setup roles and register game
        vm.startPrank(admin);

        // Register game in registry
        registry.registerGame(address(blackjack), "Blackjack");

        // Grant GAME_ROLE to blackjack on treasury
        treasury.grantRole(treasury.GAME_ROLE(), address(blackjack));

        // Add blackjack as requester on VRF consumer
        vrfConsumer.addRequester(address(blackjack));

        // Grant RESOLVER_ROLE to VRF consumer on blackjack
        blackjack.grantRole(blackjack.RESOLVER_ROLE(), address(vrfConsumer));

        vm.stopPrank();

        // Fund treasury
        vm.deal(admin, 1000 ether);
        vm.prank(admin);
        treasury.deposit{value: 1000 ether}();

        // Fund players
        vm.deal(player, 100 ether);
        vm.deal(player2, 100 ether);
    }

    // ============ Helper Functions ============

    /// @notice Create random words that will generate specific cards
    function _createRandomWordsForCards(uint8[] memory cards) internal pure returns (uint256[] memory) {
        uint256[] memory words = new uint256[](cards.length > 10 ? cards.length : 10);
        for (uint256 i = 0; i < cards.length; i++) {
            // Each card ID should be returned from BlackjackLib.generateCard
            // which uses randomWord % 52
            words[i] = cards[i];  // Simple case: card ID directly
        }
        // Fill remaining with sequential cards
        for (uint256 i = cards.length; i < 10; i++) {
            words[i] = 30 + i;  // Some other cards
        }
        return words;
    }

    /// @notice Place a bet and get the bet ID
    function _placeBet(address bettor, uint256 amount) internal returns (uint256) {
        vm.prank(bettor);
        return blackjack.placeBet{value: amount}("");
    }

    /// @notice Fulfill VRF with specific cards
    /// Cards order: player1, dealer1, player2, dealer2, then additional
    function _fulfillWithCards(uint256 requestId, uint8[] memory cards) internal {
        uint256[] memory words = _createRandomWordsForCards(cards);
        vrfCoordinator.fulfillRandomWords(requestId, words);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(blackjack.gameName(), "Blackjack");
        assertTrue(blackjack.hasRole(blackjack.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(blackjack.getHouseEdge(), BlackjackLib.HOUSE_EDGE);
    }

    function test_RevertWhen_InitializeZeroAdmin() public {
        Blackjack newImpl = new Blackjack();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeWithSelector(
                Blackjack.initialize.selector,
                address(0),
                address(casino),
                address(treasury),
                address(registry),
                address(vrfConsumer)
            )
        );
    }

    // ============ Basic Game Flow Tests ============

    function test_PlaceBet() public {
        uint256 betId = _placeBet(player, 1 ether);

        assertEq(betId, 1);
        BetLib.Bet memory bet = blackjack.getBet(betId);
        assertEq(bet.player, player);
        assertEq(bet.amount, 1 ether);
        assertEq(uint8(bet.status), uint8(BetLib.BetStatus.Pending));
    }

    function test_InitialDeal() public {
        uint256 betId = _placeBet(player, 1 ether);

        // Cards: P:Ace+Ten (blackjack), D:7+2
        uint8[] memory cards = new uint8[](4);
        cards[0] = ACE_HEARTS;      // Player card 1
        cards[1] = SEVEN_HEARTS;    // Dealer up card
        cards[2] = TEN_HEARTS;      // Player card 2
        cards[3] = TWO_HEARTS;      // Dealer hole card

        _fulfillWithCards(1, cards);

        // Player has blackjack - game should auto-resolve
        assertEq(uint8(blackjack.getGameState(betId)), uint8(BlackjackLib.GameState.Resolved));
    }

    function test_PlayerBlackjackWins() public {
        uint256 betId = _placeBet(player, 1 ether);
        uint256 playerBalanceBefore = player.balance;

        // Cards: P:Ace+10 (blackjack), D:7+5 (12)
        uint8[] memory cards = new uint8[](4);
        cards[0] = ACE_HEARTS;
        cards[1] = SEVEN_HEARTS;
        cards[2] = TEN_HEARTS;
        cards[3] = FIVE_HEARTS;

        _fulfillWithCards(1, cards);

        // Blackjack pays 3:2 = 1.5 ether profit + 1 ether bet back = 2.5 ether
        assertEq(player.balance, playerBalanceBefore + 2.5 ether);

        (,,,,BlackjackLib.Outcome outcome) = blackjack.getPlayerHand(betId, 0);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.PlayerBlackjack));
    }

    function test_DealerBlackjackWins() public {
        uint256 betId = _placeBet(player, 1 ether);
        uint256 playerBalanceBefore = player.balance;

        // Cards: P:7+5 (12), D:Ace+10 (blackjack)
        uint8[] memory cards = new uint8[](4);
        cards[0] = SEVEN_HEARTS;
        cards[1] = ACE_HEARTS;
        cards[2] = FIVE_HEARTS;
        cards[3] = TEN_HEARTS;

        _fulfillWithCards(1, cards);

        // Player loses
        assertEq(player.balance, playerBalanceBefore);

        (,,,,BlackjackLib.Outcome outcome) = blackjack.getPlayerHand(betId, 0);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.DealerBlackjack));
    }

    function test_BothBlackjackPush() public {
        uint256 betId = _placeBet(player, 1 ether);
        uint256 playerBalanceBefore = player.balance;

        // Cards: P:Ace+10 (blackjack), D:Ace+King (blackjack)
        uint8[] memory cards = new uint8[](4);
        cards[0] = ACE_HEARTS;
        cards[1] = ACE_DIAMONDS;
        cards[2] = TEN_HEARTS;
        cards[3] = KING_DIAMONDS;

        _fulfillWithCards(1, cards);

        // Push - bet returned
        assertEq(player.balance, playerBalanceBefore + 1 ether);

        (,,,,BlackjackLib.Outcome outcome) = blackjack.getPlayerHand(betId, 0);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.Push));
    }

    // ============ Player Action Tests ============

    function test_PlayerHitAndStand() public {
        uint256 betId = _placeBet(player, 1 ether);

        // Cards: P:7+5 (12), D:6+hole, then P gets 4 (16)
        uint8[] memory cards = new uint8[](10);
        cards[0] = SEVEN_HEARTS;    // P1
        cards[1] = SIX_HEARTS;      // D up
        cards[2] = FIVE_HEARTS;     // P2
        cards[3] = NINE_HEARTS;     // D hole
        cards[4] = FOUR_HEARTS;     // P hit -> 16
        cards[5] = TEN_DIAMONDS;    // D hit -> 25 (bust)

        _fulfillWithCards(1, cards);

        // Game should be in PlayerTurn
        assertEq(uint8(blackjack.getGameState(betId)), uint8(BlackjackLib.GameState.PlayerTurn));

        // Player hits
        vm.prank(player);
        blackjack.hit(betId);

        // Check hand value (7+5+4 = 16)
        (,, uint8 value,,) = blackjack.getPlayerHand(betId, 0);
        assertEq(value, 16);

        // Player stands
        vm.prank(player);
        blackjack.stand(betId);

        // Game should resolve - dealer busts (6+9+10 = 25)
        assertEq(uint8(blackjack.getGameState(betId)), uint8(BlackjackLib.GameState.Resolved));
    }

    function test_PlayerBusts() public {
        uint256 betId = _placeBet(player, 1 ether);
        uint256 playerBalanceBefore = player.balance;

        // Cards: P:10+6 (16), D:7+hole, then P gets 10 (bust)
        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = SEVEN_HEARTS;
        cards[2] = SIX_HEARTS;
        cards[3] = FIVE_HEARTS;
        cards[4] = TEN_DIAMONDS;   // P hit -> bust

        _fulfillWithCards(1, cards);

        // Player hits and busts
        vm.prank(player);
        blackjack.hit(betId);

        // Game should auto-resolve on bust
        assertEq(uint8(blackjack.getGameState(betId)), uint8(BlackjackLib.GameState.Resolved));
        assertEq(player.balance, playerBalanceBefore);  // Lost bet
    }

    function test_DoubleDown() public {
        uint256 betId = _placeBet(player, 1 ether);

        // Cards: P:5+6 (11 - good for double), D:6+hole
        uint8[] memory cards = new uint8[](10);
        cards[0] = FIVE_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SIX_DIAMONDS;
        cards[3] = TEN_HEARTS;     // D hole
        cards[4] = TEN_DIAMONDS;   // P double gets 21
        cards[5] = ACE_HEARTS;     // D hit -> 17, stands

        _fulfillWithCards(1, cards);

        uint256 playerBalanceBefore = player.balance;

        // Player doubles down (must send equal bet)
        vm.prank(player);
        blackjack.doubleDown{value: 1 ether}(betId);

        // Game should resolve (player auto-stands after double)
        assertEq(uint8(blackjack.getGameState(betId)), uint8(BlackjackLib.GameState.Resolved));

        // Player wins with 21 vs 17: doubled bet (2 ether) + 2 ether payout = 4 ether
        assertEq(player.balance, playerBalanceBefore - 1 ether + 4 ether);
    }

    function test_DoubleDownRequiresExactAmount() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](10);
        cards[0] = FIVE_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SIX_DIAMONDS;
        cards[3] = TEN_HEARTS;

        _fulfillWithCards(1, cards);

        // Try to double with wrong amount
        vm.prank(player);
        vm.expectRevert(Errors.InvalidAmount.selector);
        blackjack.doubleDown{value: 0.5 ether}(betId);
    }

    function test_CannotHitAfterStand() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SEVEN_HEARTS;
        cards[3] = TEN_DIAMONDS;

        _fulfillWithCards(1, cards);

        vm.prank(player);
        blackjack.stand(betId);

        // Game is resolved, can't hit anymore
        vm.prank(player);
        vm.expectRevert(Blackjack.InvalidGameState.selector);
        blackjack.hit(betId);
    }

    function test_RevertWhen_UnauthorizedAction() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SEVEN_HEARTS;
        cards[3] = TEN_DIAMONDS;

        _fulfillWithCards(1, cards);

        // Player2 tries to hit on player1's game
        vm.prank(player2);
        vm.expectRevert(Errors.Unauthorized.selector);
        blackjack.hit(betId);
    }

    // ============ Dealer Logic Tests ============

    function test_DealerHitsOnSoft17() public {
        uint256 betId = _placeBet(player, 1 ether);

        // Cards: P:10+8 (18), D:Ace+6 (soft 17, must hit)
        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = ACE_HEARTS;     // D up: Ace
        cards[2] = EIGHT_HEARTS;
        cards[3] = SIX_HEARTS;     // D hole: 6 -> soft 17
        cards[4] = THREE_HEARTS;   // D hit -> 20

        _fulfillWithCards(1, cards);

        vm.prank(player);
        blackjack.stand(betId);

        // Dealer should have hit on soft 17 and gotten 20
        (uint8[] memory dealerCards, uint8 dealerValue,) = blackjack.getDealerHand(betId);
        assertEq(dealerCards.length, 3);  // Had to hit
        assertEq(dealerValue, 20);
    }

    function test_DealerStandsOn17() public {
        uint256 betId = _placeBet(player, 1 ether);

        // Cards: P:10+8 (18), D:10+7 (hard 17, stands)
        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = TEN_DIAMONDS;   // D up: 10
        cards[2] = EIGHT_HEARTS;
        cards[3] = SEVEN_HEARTS;   // D hole: 7 -> hard 17

        _fulfillWithCards(1, cards);

        vm.prank(player);
        blackjack.stand(betId);

        // Dealer should stand on hard 17
        (uint8[] memory dealerCards, uint8 dealerValue,) = blackjack.getDealerHand(betId);
        assertEq(dealerCards.length, 2);  // No hit
        assertEq(dealerValue, 17);

        // Player wins 18 vs 17
        (,,,,BlackjackLib.Outcome outcome) = blackjack.getPlayerHand(betId, 0);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.PlayerWin));
    }

    function test_DealerBusts() public {
        uint256 betId = _placeBet(player, 1 ether);
        uint256 playerBalanceBefore = player.balance;

        // Cards: P:10+7 (17), D:6+9 (15, must hit), gets 10 (bust)
        uint8[] memory cards = new uint8[](10);
        cards[0] = TEN_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SEVEN_HEARTS;
        cards[3] = NINE_HEARTS;    // D: 15
        cards[4] = TEN_DIAMONDS;   // D bust

        _fulfillWithCards(1, cards);

        vm.prank(player);
        blackjack.stand(betId);

        // Player wins - dealer busted
        (,,,,BlackjackLib.Outcome outcome) = blackjack.getPlayerHand(betId, 0);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.DealerBust));

        // Payout: 1 ether bet + 1 ether win = 2 ether
        assertEq(player.balance, playerBalanceBefore + 2 ether);
    }

    // ============ View Function Tests ============

    function test_GetPlayerHand() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](4);
        cards[0] = TEN_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SEVEN_HEARTS;
        cards[3] = FIVE_HEARTS;

        _fulfillWithCards(1, cards);

        (uint8[] memory cardIds, uint256 bet, uint8 value, bool isSoft, BlackjackLib.Outcome outcome) =
            blackjack.getPlayerHand(betId, 0);

        assertEq(cardIds.length, 2);
        assertEq(cardIds[0], TEN_HEARTS);
        assertEq(cardIds[1], SEVEN_HEARTS);
        assertEq(bet, 1 ether);
        assertEq(value, 17);
        assertFalse(isSoft);
        assertEq(uint8(outcome), uint8(BlackjackLib.Outcome.Pending));
    }

    function test_GetDealerHand() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](4);
        cards[0] = TEN_HEARTS;
        cards[1] = SIX_HEARTS;
        cards[2] = SEVEN_HEARTS;
        cards[3] = FIVE_HEARTS;

        _fulfillWithCards(1, cards);

        // During player turn, only upcard visible
        (uint8[] memory cardIds, uint8 value, bool allRevealed) = blackjack.getDealerHand(betId);

        assertEq(cardIds.length, 2);
        assertFalse(allRevealed);
        assertEq(value, 6);  // Only upcard value
    }

    function test_CanTakeAction() public {
        uint256 betId = _placeBet(player, 1 ether);

        uint8[] memory cards = new uint8[](4);
        cards[0] = FIVE_HEARTS;    // Good for split
        cards[1] = SIX_HEARTS;
        cards[2] = FIVE_DIAMONDS;
        cards[3] = TEN_HEARTS;

        _fulfillWithCards(1, cards);

        assertTrue(blackjack.canTakeAction(betId, BlackjackLib.Action.Hit));
        assertTrue(blackjack.canTakeAction(betId, BlackjackLib.Action.Stand));
        assertTrue(blackjack.canTakeAction(betId, BlackjackLib.Action.DoubleDown));
        assertTrue(blackjack.canTakeAction(betId, BlackjackLib.Action.Split));
    }

    // ============ Error Cases ============

    function test_RevertWhen_BelowMinBet() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Errors.BetTooSmall.selector, 0.0001 ether, 0.001 ether));
        blackjack.placeBet{value: 0.0001 ether}("");
    }

    function test_RevertWhen_AboveMaxBet() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Errors.BetTooLarge.selector, 100 ether, 10 ether));
        blackjack.placeBet{value: 100 ether}("");
    }

    function test_RevertWhen_Paused() public {
        vm.prank(admin);
        blackjack.pause();

        vm.prank(player);
        vm.expectRevert();
        blackjack.placeBet{value: 1 ether}("");
    }

    // ============ Multiple Players ============

    function test_MultiplePlayers() public {
        uint256 betId1 = _placeBet(player, 1 ether);
        uint256 betId2 = _placeBet(player2, 1 ether);

        assertEq(betId1, 1);
        assertEq(betId2, 2);

        BetLib.Bet memory bet1 = blackjack.getBet(betId1);
        BetLib.Bet memory bet2 = blackjack.getBet(betId2);

        assertEq(bet1.player, player);
        assertEq(bet2.player, player2);
    }

    // ============ House Edge ============

    function test_GetHouseEdge() public view {
        assertEq(blackjack.getHouseEdge(), 50);  // 0.5%
    }

    // ============ Card Value Tests (Library) ============

    function test_CardValueCalculation() public pure {
        // Test Ace (rank 0)
        assertEq(BlackjackLib.getCardValue(0), 11);

        // Test number cards (ranks 1-8 = values 2-9)
        assertEq(BlackjackLib.getCardValue(1), 2);
        assertEq(BlackjackLib.getCardValue(8), 9);

        // Test face cards (ranks 9-12 = value 10)
        assertEq(BlackjackLib.getCardValue(9), 10);   // 10
        assertEq(BlackjackLib.getCardValue(10), 10);  // J
        assertEq(BlackjackLib.getCardValue(11), 10);  // Q
        assertEq(BlackjackLib.getCardValue(12), 10);  // K
    }

    function test_HandValueWithSoftAce() public pure {
        // Ace + 6 = soft 17
        BlackjackLib.Card[] memory cards = new BlackjackLib.Card[](2);
        cards[0] = BlackjackLib.Card({id: 0, revealed: true});   // Ace
        cards[1] = BlackjackLib.Card({id: 5, revealed: true});   // 6

        (uint8 value, bool isSoft) = BlackjackLib.calculateHandValue(cards);
        assertEq(value, 17);
        assertTrue(isSoft);
    }

    function test_HandValueWithHardAce() public pure {
        // Ace + 6 + 10 = hard 17 (Ace becomes 1)
        BlackjackLib.Card[] memory cards = new BlackjackLib.Card[](3);
        cards[0] = BlackjackLib.Card({id: 0, revealed: true});   // Ace
        cards[1] = BlackjackLib.Card({id: 5, revealed: true});   // 6
        cards[2] = BlackjackLib.Card({id: 9, revealed: true});   // 10

        (uint8 value, bool isSoft) = BlackjackLib.calculateHandValue(cards);
        assertEq(value, 17);
        assertFalse(isSoft);
    }

    function test_IsBlackjack() public pure {
        // Ace + King = blackjack
        BlackjackLib.Card[] memory bj = new BlackjackLib.Card[](2);
        bj[0] = BlackjackLib.Card({id: 0, revealed: true});    // Ace
        bj[1] = BlackjackLib.Card({id: 12, revealed: true});   // King

        assertTrue(BlackjackLib.isBlackjack(bj));

        // 10 + 7 + 4 = 21 but not blackjack
        BlackjackLib.Card[] memory notBj = new BlackjackLib.Card[](3);
        notBj[0] = BlackjackLib.Card({id: 9, revealed: true});
        notBj[1] = BlackjackLib.Card({id: 6, revealed: true});
        notBj[2] = BlackjackLib.Card({id: 3, revealed: true});

        assertFalse(BlackjackLib.isBlackjack(notBj));
    }

    function test_CanSplit() public pure {
        // Two 5s can split
        BlackjackLib.Card[] memory fives = new BlackjackLib.Card[](2);
        fives[0] = BlackjackLib.Card({id: 4, revealed: true});   // 5 of hearts
        fives[1] = BlackjackLib.Card({id: 17, revealed: true});  // 5 of diamonds

        assertTrue(BlackjackLib.canSplit(fives));

        // 10 and King can split (both value 10)
        BlackjackLib.Card[] memory tens = new BlackjackLib.Card[](2);
        tens[0] = BlackjackLib.Card({id: 9, revealed: true});    // 10
        tens[1] = BlackjackLib.Card({id: 12, revealed: true});   // King

        assertTrue(BlackjackLib.canSplit(tens));

        // 5 and 6 cannot split
        BlackjackLib.Card[] memory noSplit = new BlackjackLib.Card[](2);
        noSplit[0] = BlackjackLib.Card({id: 4, revealed: true});
        noSplit[1] = BlackjackLib.Card({id: 5, revealed: true});

        assertFalse(BlackjackLib.canSplit(noSplit));
    }

    // ============ Payout Tests ============

    function test_PayoutCalculation() public pure {
        // Blackjack pays 3:2
        uint256 bjPayout = BlackjackLib.calculatePayout(1 ether, BlackjackLib.Outcome.PlayerBlackjack, false);
        assertEq(bjPayout, 2.5 ether);  // 1 + 1.5

        // Regular win pays 1:1
        uint256 winPayout = BlackjackLib.calculatePayout(1 ether, BlackjackLib.Outcome.PlayerWin, false);
        assertEq(winPayout, 2 ether);  // 1 + 1

        // Doubled win pays 2:2
        uint256 doubledPayout = BlackjackLib.calculatePayout(1 ether, BlackjackLib.Outcome.PlayerWin, true);
        assertEq(doubledPayout, 4 ether);  // 2 + 2

        // Push returns bet
        uint256 pushPayout = BlackjackLib.calculatePayout(1 ether, BlackjackLib.Outcome.Push, false);
        assertEq(pushPayout, 1 ether);

        // Loss pays nothing
        uint256 lossPayout = BlackjackLib.calculatePayout(1 ether, BlackjackLib.Outcome.DealerWin, false);
        assertEq(lossPayout, 0);
    }
}
