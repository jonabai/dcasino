// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseGameVRF} from "../abstracts/BaseGameVRF.sol";
import {IGame} from "../interfaces/IGame.sol";
import {BetLib} from "../libraries/BetLib.sol";
import {BlackjackLib} from "../libraries/BlackjackLib.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title Blackjack - Standard Casino Blackjack
/// @notice Implements standard Vegas blackjack rules with hit, stand, double down, and split
/// @dev Extends BaseGameVRF for VRF-based card dealing
contract Blackjack is BaseGameVRF {
    using BlackjackLib for BlackjackLib.Card[];

    // ============ Constants ============

    /// @notice Number of random words to request (enough for full game)
    uint8 public constant RANDOM_WORDS_NEEDED = 10;

    /// @notice Blackjack pays 3:2
    uint256 public constant BLACKJACK_PAYOUT_NUMERATOR = 3;
    uint256 public constant BLACKJACK_PAYOUT_DENOMINATOR = 2;

    // ============ Storage ============

    /// @notice Mapping from bet ID to blackjack game state
    mapping(uint256 => GameStorage) internal _games;

    /// @notice Storage gap for future upgrades
    uint256[38] private __gap_blackjack;

    // ============ Structs ============

    /// @notice Stored game state (optimized for storage)
    struct GameStorage {
        uint256 usedCards;          // Bitmap of dealt cards (52 bits used)
        uint256[] randomWords;      // VRF random words for card generation
        uint8 randomWordIndex;      // Current index into random words
        uint8 numPlayerHands;       // Number of player hands (1-4)
        uint8 activeHandIndex;      // Currently active hand
        uint8 cardsDealt;           // Total cards dealt
        BlackjackLib.GameState state;
        bool insuranceTaken;
        uint256 insuranceBet;
        HandStorage[] playerHands;
        HandStorage dealerHand;
    }

    /// @notice Stored hand data
    struct HandStorage {
        uint8[] cardIds;
        uint256 bet;
        bool doubled;
        bool fromSplit;
        bool stood;
        bool busted;
        BlackjackLib.Outcome outcome;
    }

    // ============ Events ============

    /// @notice Emitted when initial cards are dealt
    event GameStarted(
        uint256 indexed betId,
        uint8 playerCard1,
        uint8 playerCard2,
        uint8 dealerUpCard
    );

    /// @notice Emitted when a card is dealt
    event CardDealt(
        uint256 indexed betId,
        uint8 handIndex,
        uint8 cardId,
        bool isPlayer
    );

    /// @notice Emitted when player takes an action
    event PlayerAction(
        uint256 indexed betId,
        uint8 handIndex,
        BlackjackLib.Action action
    );

    /// @notice Emitted when dealer reveals hole card
    event DealerRevealed(uint256 indexed betId, uint8 holeCard);

    /// @notice Emitted when a hand is resolved
    event HandResolved(
        uint256 indexed betId,
        uint8 handIndex,
        BlackjackLib.Outcome outcome,
        uint256 payout
    );

    /// @notice Emitted for insurance result
    event InsuranceResult(uint256 indexed betId, bool dealerHasBlackjack, uint256 payout);

    // ============ Errors ============

    /// @notice Invalid action for current game state
    error InvalidAction();

    /// @notice Game not in correct state
    error InvalidGameState();

    /// @notice Hand already complete
    error HandComplete();

    /// @notice Not enough funds for action
    error InsufficientFunds();

    /// @notice Cannot split these cards
    error CannotSplit();

    /// @notice Insurance not available
    error InsuranceNotAvailable();

    /// @notice Game not found
    error GameNotFound();

    // ============ Initializer ============

    /// @notice Initialize the Blackjack game
    /// @param admin Admin address
    /// @param casinoAddress Casino contract address
    /// @param treasuryAddress Treasury contract address
    /// @param registryAddress Game registry address
    /// @param vrfConsumerAddress VRF consumer address
    function initialize(
        address admin,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress,
        address vrfConsumerAddress
    ) external initializer {
        __BaseGameVRF_init(
            admin,
            "Blackjack",
            casinoAddress,
            treasuryAddress,
            registryAddress,
            vrfConsumerAddress
        );
    }

    // ============ View Functions ============

    /// @inheritdoc IGame
    function getHouseEdge() external pure override returns (uint256) {
        return BlackjackLib.HOUSE_EDGE;
    }

    /// @notice Get game state for a bet
    /// @param betId The bet ID
    /// @return state The game state enum
    function getGameState(uint256 betId) external view returns (BlackjackLib.GameState) {
        return _games[betId].state;
    }

    /// @notice Get player hand info
    /// @param betId The bet ID
    /// @param handIndex The hand index (0 for main hand)
    /// @return cardIds Array of card IDs
    /// @return bet The bet amount for this hand
    /// @return value Current hand value
    /// @return isSoft Whether hand is soft
    /// @return outcome The hand outcome
    function getPlayerHand(uint256 betId, uint8 handIndex)
        external
        view
        returns (
            uint8[] memory cardIds,
            uint256 bet,
            uint8 value,
            bool isSoft,
            BlackjackLib.Outcome outcome
        )
    {
        GameStorage storage game = _games[betId];
        require(handIndex < game.numPlayerHands, "Invalid hand index");

        HandStorage storage hand = game.playerHands[handIndex];
        cardIds = hand.cardIds;
        bet = hand.bet;
        outcome = hand.outcome;

        // Calculate value
        BlackjackLib.Card[] memory cards = _toCards(hand.cardIds, true);
        (value, isSoft) = BlackjackLib.calculateHandValue(cards);
    }

    /// @notice Get dealer hand info (only shows revealed cards)
    /// @param betId The bet ID
    /// @return cardIds Array of card IDs
    /// @return value Current visible hand value
    /// @return allRevealed Whether all cards are revealed
    function getDealerHand(uint256 betId)
        external
        view
        returns (uint8[] memory cardIds, uint8 value, bool allRevealed)
    {
        GameStorage storage game = _games[betId];
        HandStorage storage hand = game.dealerHand;

        cardIds = hand.cardIds;
        allRevealed = game.state == BlackjackLib.GameState.Resolved ||
                      game.state == BlackjackLib.GameState.DealerTurn;

        // Calculate visible value
        BlackjackLib.Card[] memory cards = _toCards(hand.cardIds, allRevealed);
        (value,) = BlackjackLib.calculateHandValue(cards);
    }

    /// @notice Check if player can take a specific action
    /// @param betId The bet ID
    /// @param action The action to check
    /// @return canTake Whether the action is valid
    function canTakeAction(uint256 betId, BlackjackLib.Action action) external view returns (bool) {
        GameStorage storage game = _games[betId];
        if (game.state != BlackjackLib.GameState.PlayerTurn) return false;

        HandStorage storage hand = game.playerHands[game.activeHandIndex];
        BlackjackLib.Hand memory handMem = _toHand(hand, true);

        return BlackjackLib.validateAction(handMem, action, game.state, game.numPlayerHands);
    }

    // ============ Player Action Functions ============

    /// @notice Player hits (takes another card)
    /// @param betId The bet ID
    function hit(uint256 betId) external nonReentrant {
        GameStorage storage game = _games[betId];
        BetLib.Bet storage bet = _bets[betId];

        _validatePlayerAction(game, bet, BlackjackLib.Action.Hit);

        // Deal a card to active hand
        uint8 cardId = _dealCard(game);
        game.playerHands[game.activeHandIndex].cardIds.push(cardId);

        emit CardDealt(betId, game.activeHandIndex, cardId, true);
        emit PlayerAction(betId, game.activeHandIndex, BlackjackLib.Action.Hit);

        // Check if busted
        BlackjackLib.Card[] memory cards = _toCards(
            game.playerHands[game.activeHandIndex].cardIds,
            true
        );

        if (BlackjackLib.isBusted(cards)) {
            game.playerHands[game.activeHandIndex].busted = true;
            game.playerHands[game.activeHandIndex].outcome = BlackjackLib.Outcome.PlayerBust;
            _advanceHand(betId, game);
        }
    }

    /// @notice Player stands (keeps current hand)
    /// @param betId The bet ID
    function stand(uint256 betId) external nonReentrant {
        GameStorage storage game = _games[betId];
        BetLib.Bet storage bet = _bets[betId];

        _validatePlayerAction(game, bet, BlackjackLib.Action.Stand);

        game.playerHands[game.activeHandIndex].stood = true;

        emit PlayerAction(betId, game.activeHandIndex, BlackjackLib.Action.Stand);

        _advanceHand(betId, game);
    }

    /// @notice Player doubles down (double bet, get one card, auto-stand)
    /// @param betId The bet ID
    function doubleDown(uint256 betId) external payable nonReentrant {
        GameStorage storage game = _games[betId];
        BetLib.Bet storage bet = _bets[betId];

        _validatePlayerAction(game, bet, BlackjackLib.Action.DoubleDown);

        HandStorage storage hand = game.playerHands[game.activeHandIndex];

        // Must send exact bet amount to double
        if (msg.value != hand.bet) revert Errors.InvalidAmount();

        // Reserve additional funds
        uint256 additionalPayout = msg.value * 2;  // Worst case: blackjack on doubled hand
        if (!_treasury.canPayout(additionalPayout)) {
            revert Errors.InsufficientTreasuryBalance();
        }

        _treasury.receiveBet{value: msg.value}();
        _treasury.reserveFunds(additionalPayout);

        // Update bet tracking
        bet.amount += msg.value;
        bet.potentialPayout += additionalPayout;

        // Mark as doubled and deal one card
        hand.doubled = true;
        uint8 cardId = _dealCard(game);
        hand.cardIds.push(cardId);

        emit CardDealt(betId, game.activeHandIndex, cardId, true);
        emit PlayerAction(betId, game.activeHandIndex, BlackjackLib.Action.DoubleDown);

        // Check for bust
        BlackjackLib.Card[] memory cards = _toCards(hand.cardIds, true);
        if (BlackjackLib.isBusted(cards)) {
            hand.busted = true;
            hand.outcome = BlackjackLib.Outcome.PlayerBust;
        } else {
            hand.stood = true;  // Auto-stand after double
        }

        _advanceHand(betId, game);
    }

    /// @notice Player splits a pair into two hands
    /// @param betId The bet ID
    function split(uint256 betId) external payable nonReentrant {
        GameStorage storage game = _games[betId];
        BetLib.Bet storage bet = _bets[betId];

        _validatePlayerAction(game, bet, BlackjackLib.Action.Split);

        HandStorage storage hand = game.playerHands[game.activeHandIndex];

        // Verify can split
        BlackjackLib.Card[] memory cards = _toCards(hand.cardIds, true);
        if (!BlackjackLib.canSplit(cards)) revert CannotSplit();
        if (game.numPlayerHands >= BlackjackLib.MAX_SPLITS + 1) revert CannotSplit();

        // Must send exact bet amount
        if (msg.value != hand.bet) revert Errors.InvalidAmount();

        // Reserve funds for new hand
        uint256 newHandPayout = msg.value * 2;
        if (!_treasury.canPayout(newHandPayout)) {
            revert Errors.InsufficientTreasuryBalance();
        }

        _treasury.receiveBet{value: msg.value}();
        _treasury.reserveFunds(newHandPayout);

        bet.amount += msg.value;
        bet.potentialPayout += newHandPayout;

        // Create new hand with second card
        uint8 secondCard = hand.cardIds[1];
        hand.cardIds.pop();  // Remove second card from original hand

        // Add new hand
        HandStorage storage newHand = game.playerHands.push();
        newHand.cardIds.push(secondCard);
        newHand.bet = hand.bet;
        newHand.fromSplit = true;
        hand.fromSplit = true;
        game.numPlayerHands++;

        // Deal a card to each hand
        uint8 card1 = _dealCard(game);
        hand.cardIds.push(card1);
        emit CardDealt(betId, game.activeHandIndex, card1, true);

        uint8 card2 = _dealCard(game);
        newHand.cardIds.push(card2);
        emit CardDealt(betId, game.numPlayerHands - 1, card2, true);

        emit PlayerAction(betId, game.activeHandIndex, BlackjackLib.Action.Split);
    }

    /// @notice Player takes insurance (when dealer shows Ace)
    /// @param betId The bet ID
    function takeInsurance(uint256 betId) external payable nonReentrant {
        GameStorage storage game = _games[betId];
        BetLib.Bet storage bet = _bets[betId];

        if (bet.player != msg.sender) revert Errors.Unauthorized();
        if (game.state != BlackjackLib.GameState.PlayerTurn) revert InvalidGameState();
        if (game.insuranceTaken) revert InsuranceNotAvailable();

        // Check dealer shows Ace
        BlackjackLib.Card[] memory dealerCards = _toCards(game.dealerHand.cardIds, false);
        if (!BlackjackLib.dealerShowsAce(dealerCards)) revert InsuranceNotAvailable();

        // Insurance is half the original bet
        uint256 insuranceAmount = game.playerHands[0].bet / 2;
        if (msg.value != insuranceAmount) revert Errors.InvalidAmount();

        _treasury.receiveBet{value: msg.value}();
        _treasury.reserveFunds(msg.value * 3);  // 2:1 payout potential

        game.insuranceTaken = true;
        game.insuranceBet = msg.value;
        bet.amount += msg.value;
        bet.potentialPayout += msg.value * 3;
    }

    // ============ Internal Functions ============

    /// @notice Calculate potential payout for bet (worst case for treasury)
    function _calculatePotentialPayout(uint256 amount, bytes calldata /* betData */)
        internal
        pure
        override
        returns (uint256)
    {
        // Worst case: blackjack pays 3:2, plus original bet back
        // Also account for potential splits (up to 4 hands) and doubles
        // Max theoretical payout: 4 hands * 2 (doubled) * 2.5 (BJ payout) = 20x
        // But more realistic max: 4 * 2 * 2 = 16x (regular wins on all doubled hands)
        return amount * 3;  // Conservative estimate: 3x for single hand with BJ potential
    }

    /// @notice Override resolveBet to handle Blackjack's multi-step flow
    /// @dev Blackjack differs from single-step games - the initial VRF callback
    /// may start a player turn instead of immediately resolving
    function resolveBet(uint256 betId, uint256[] calldata randomWords)
        external
        override
        onlyRole(RESOLVER_ROLE)
    {
        BetLib.Bet storage bet = _bets[betId];

        if (bet.id == 0) revert Errors.BetNotFound(betId);
        if (BetLib.isResolved(bet)) revert Errors.BetAlreadyResolved(betId);

        GameStorage storage game = _games[betId];

        // Store random words for later card dealing
        for (uint256 i = 0; i < randomWords.length; i++) {
            game.randomWords.push(randomWords[i]);
        }

        // Deal initial cards
        _dealInitialCards(betId, game);

        // Check for blackjacks
        BlackjackLib.Card[] memory dealerCards = _toCards(game.dealerHand.cardIds, true);
        bool dealerBJ = BlackjackLib.isBlackjack(dealerCards);

        BlackjackLib.Card[] memory playerCards = _toCards(game.playerHands[0].cardIds, true);
        bool playerBJ = BlackjackLib.isBlackjack(playerCards);

        // If either has blackjack, resolve immediately
        if (playerBJ || dealerBJ) {
            _resolveBlackjacks(betId, game, bet, playerBJ, dealerBJ);
            return;
        }

        // Otherwise, game continues - player turn
        // Don't call base resolution, just set state
        game.state = BlackjackLib.GameState.PlayerTurn;
    }

    /// @notice Resolve bet with VRF randomness - NOT USED for Blackjack
    /// @dev Blackjack overrides resolveBet directly
    function _resolveBet(BetLib.Bet storage /* bet */, uint256[] calldata /* randomWords */)
        internal
        pure
        override
        returns (bool, uint256)
    {
        // This should never be called - Blackjack overrides resolveBet
        revert("Use resolveBet");
    }

    /// @notice Deal initial cards (2 to player, 2 to dealer)
    function _dealInitialCards(uint256 betId, GameStorage storage game) internal {
        // Initialize player hand
        HandStorage storage playerHand = game.playerHands.push();
        playerHand.bet = _bets[betId].amount;
        game.numPlayerHands = 1;

        // Deal: Player, Dealer, Player, Dealer
        uint8 p1 = _dealCard(game);
        playerHand.cardIds.push(p1);

        uint8 d1 = _dealCard(game);
        game.dealerHand.cardIds.push(d1);

        uint8 p2 = _dealCard(game);
        playerHand.cardIds.push(p2);

        uint8 d2 = _dealCard(game);
        game.dealerHand.cardIds.push(d2);

        game.state = BlackjackLib.GameState.Dealing;

        emit GameStarted(betId, p1, p2, d1);
    }

    /// @notice Deal a card from the random words
    function _dealCard(GameStorage storage game) internal returns (uint8) {
        require(game.randomWordIndex < game.randomWords.length, "Out of randomness");

        uint256 randomWord = game.randomWords[game.randomWordIndex];
        game.randomWordIndex++;

        (uint8 cardId, uint256 newUsedCards) = BlackjackLib.generateCard(randomWord, game.usedCards);
        game.usedCards = newUsedCards;
        game.cardsDealt++;

        return cardId;
    }

    /// @notice Resolve blackjack situations (handles full resolution including treasury)
    function _resolveBlackjacks(
        uint256 betId,
        GameStorage storage game,
        BetLib.Bet storage bet,
        bool playerBJ,
        bool dealerBJ
    ) internal {
        game.state = BlackjackLib.GameState.Resolved;

        HandStorage storage hand = game.playerHands[0];
        uint256 payout;
        bool won;

        if (playerBJ && dealerBJ) {
            hand.outcome = BlackjackLib.Outcome.Push;
            payout = hand.bet;  // Return original bet
            won = false;  // Not a win, just push
        } else if (playerBJ) {
            hand.outcome = BlackjackLib.Outcome.PlayerBlackjack;
            // Blackjack pays 3:2
            payout = hand.bet + (hand.bet * BLACKJACK_PAYOUT_NUMERATOR / BLACKJACK_PAYOUT_DENOMINATOR);
            won = true;
        } else {
            hand.outcome = BlackjackLib.Outcome.DealerBlackjack;
            payout = 0;
            won = false;
        }

        emit DealerRevealed(betId, game.dealerHand.cardIds[1]);
        emit HandResolved(betId, 0, hand.outcome, payout);

        // Handle treasury operations
        if (payout > 0) {
            BetLib.markAsWon(bet, payout);
            _treasury.processPayout(bet.player, payout);
            // Release excess reserved funds
            if (bet.potentialPayout > payout) {
                _treasury.releaseFunds(bet.potentialPayout - payout);
            }
        } else {
            BetLib.markAsLost(bet);
            _treasury.releaseFunds(bet.potentialPayout);
        }

        // Collect fee only on actual losses (not pushes)
        if (hand.outcome != BlackjackLib.Outcome.Push) {
            uint256 fee = (bet.amount * _treasury.feePercentage()) / 10_000;
            if (fee > 0) {
                _treasury.collectFee(fee);
            }
        }

        _removePendingBet(betId);
        emit BetResolved(betId, bet.player, payout, won);
    }

    /// @notice Validate player action
    function _validatePlayerAction(
        GameStorage storage game,
        BetLib.Bet storage bet,
        BlackjackLib.Action action
    ) internal view {
        if (bet.player != msg.sender) revert Errors.Unauthorized();
        if (game.state != BlackjackLib.GameState.PlayerTurn) revert InvalidGameState();

        HandStorage storage hand = game.playerHands[game.activeHandIndex];
        if (hand.stood || hand.busted) revert HandComplete();

        // Validate specific action
        BlackjackLib.Hand memory handMem = _toHand(hand, true);
        if (!BlackjackLib.validateAction(handMem, action, game.state, game.numPlayerHands)) {
            revert InvalidAction();
        }
    }

    /// @notice Advance to next hand or dealer turn
    function _advanceHand(uint256 betId, GameStorage storage game) internal {
        // Check if there are more hands to play
        for (uint8 i = game.activeHandIndex + 1; i < game.numPlayerHands; i++) {
            if (!game.playerHands[i].stood && !game.playerHands[i].busted) {
                game.activeHandIndex = i;
                return;
            }
        }

        // All hands complete - dealer's turn
        _playDealer(betId, game);
    }

    /// @notice Play out dealer's hand
    function _playDealer(uint256 betId, GameStorage storage game) internal {
        game.state = BlackjackLib.GameState.DealerTurn;

        // Reveal hole card
        emit DealerRevealed(betId, game.dealerHand.cardIds[1]);

        // Check if any player hands are still in play (not busted)
        bool anyHandInPlay = false;
        for (uint8 i = 0; i < game.numPlayerHands; i++) {
            if (!game.playerHands[i].busted) {
                anyHandInPlay = true;
                break;
            }
        }

        // If all player hands busted, no need for dealer to draw
        if (!anyHandInPlay) {
            _finalizeGame(betId, game);
            return;
        }

        // Dealer draws cards
        BlackjackLib.Card[] memory dealerCards = _toCards(game.dealerHand.cardIds, true);
        (uint8 value, bool isSoft) = BlackjackLib.calculateFullHandValue(dealerCards);

        while (BlackjackLib.dealerShouldHit(value, isSoft)) {
            uint8 cardId = _dealCard(game);
            game.dealerHand.cardIds.push(cardId);

            emit CardDealt(betId, 0, cardId, false);

            dealerCards = _toCards(game.dealerHand.cardIds, true);
            (value, isSoft) = BlackjackLib.calculateFullHandValue(dealerCards);
        }

        // Check if dealer busted
        if (value > BlackjackLib.BLACKJACK) {
            game.dealerHand.busted = true;
        }

        _finalizeGame(betId, game);
    }

    /// @notice Finalize game and process payouts
    function _finalizeGame(uint256 betId, GameStorage storage game) internal {
        game.state = BlackjackLib.GameState.Resolved;

        BetLib.Bet storage bet = _bets[betId];
        uint256 totalPayout = 0;
        bool anyWin = false;

        // Get dealer final value
        BlackjackLib.Card[] memory dealerCards = _toCards(game.dealerHand.cardIds, true);
        (uint8 dealerValue,) = BlackjackLib.calculateFullHandValue(dealerCards);
        bool dealerBusted = dealerValue > BlackjackLib.BLACKJACK;
        bool dealerBJ = BlackjackLib.isBlackjack(dealerCards);

        // Process each player hand
        for (uint8 i = 0; i < game.numPlayerHands; i++) {
            HandStorage storage hand = game.playerHands[i];

            // Skip already resolved hands
            if (hand.outcome != BlackjackLib.Outcome.Pending &&
                hand.outcome != BlackjackLib.Outcome.PlayerBust) {
                if (hand.outcome == BlackjackLib.Outcome.PlayerBust) {
                    emit HandResolved(betId, i, hand.outcome, 0);
                }
                continue;
            }

            BlackjackLib.Card[] memory playerCards = _toCards(hand.cardIds, true);
            (uint8 playerValue,) = BlackjackLib.calculateFullHandValue(playerCards);
            bool playerBJ = BlackjackLib.isBlackjack(playerCards) && !hand.fromSplit;

            // Determine outcome
            hand.outcome = BlackjackLib.determineOutcome(
                playerValue,
                dealerValue,
                playerBJ,
                dealerBJ,
                hand.busted,
                dealerBusted
            );

            // Calculate payout
            uint256 handPayout = BlackjackLib.calculatePayout(hand.bet, hand.outcome, hand.doubled);
            totalPayout += handPayout;

            if (handPayout > 0) {
                anyWin = true;
            }

            emit HandResolved(betId, i, hand.outcome, handPayout);
        }

        // Process insurance if taken
        if (game.insuranceTaken) {
            uint256 insurancePayout = BlackjackLib.calculateInsurancePayout(game.insuranceBet, dealerBJ);
            totalPayout += insurancePayout;
            emit InsuranceResult(betId, dealerBJ, insurancePayout);
        }

        // Update bet status and process treasury
        if (totalPayout > 0) {
            BetLib.markAsWon(bet, totalPayout);
            _treasury.processPayout(bet.player, totalPayout);
        } else {
            BetLib.markAsLost(bet);
        }

        // Release excess reserved funds
        if (bet.potentialPayout > totalPayout) {
            _treasury.releaseFunds(bet.potentialPayout - totalPayout);
        }

        // Collect fee
        uint256 fee = (bet.amount * _treasury.feePercentage()) / 10_000;
        if (fee > 0) {
            _treasury.collectFee(fee);
        }

        _removePendingBet(betId);
        emit BetResolved(betId, bet.player, totalPayout, anyWin);
    }

    /// @notice Convert card IDs to Card structs
    function _toCards(uint8[] storage cardIds, bool allRevealed)
        internal
        view
        returns (BlackjackLib.Card[] memory)
    {
        BlackjackLib.Card[] memory cards = new BlackjackLib.Card[](cardIds.length);
        for (uint256 i = 0; i < cardIds.length; i++) {
            cards[i] = BlackjackLib.Card({
                id: cardIds[i],
                revealed: allRevealed || i == 0  // First card always visible for dealer
            });
        }
        return cards;
    }

    /// @notice Convert HandStorage to Hand memory
    function _toHand(HandStorage storage hs, bool allRevealed)
        internal
        view
        returns (BlackjackLib.Hand memory)
    {
        BlackjackLib.Card[] memory cards = _toCards(hs.cardIds, allRevealed);
        return BlackjackLib.Hand({
            cards: cards,
            bet: hs.bet,
            doubled: hs.doubled,
            fromSplit: hs.fromSplit,
            stood: hs.stood,
            busted: hs.busted,
            outcome: hs.outcome
        });
    }

    /// @notice Override to set VRF numWords
    function _getNumWords() internal pure returns (uint32) {
        return RANDOM_WORDS_NEEDED;
    }
}
