// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BlackjackLib - Blackjack Game Library
/// @notice Provides card handling, hand calculations, and game logic for Blackjack
/// @dev Uses a single 52-card deck, standard Vegas rules
library BlackjackLib {
    // ============ Constants ============

    /// @notice Number of cards in a deck
    uint8 public constant DECK_SIZE = 52;

    /// @notice Blackjack value
    uint8 public constant BLACKJACK = 21;

    /// @notice Dealer must stand on this value
    uint8 public constant DEALER_STAND = 17;

    /// @notice House edge in basis points (0.5% with basic strategy)
    uint256 public constant HOUSE_EDGE = 50;

    /// @notice Maximum cards in a hand (5 card charlie rule not implemented)
    uint8 public constant MAX_HAND_SIZE = 11;

    /// @notice Maximum number of splits allowed
    uint8 public constant MAX_SPLITS = 3;

    // ============ Enums ============

    /// @notice Card suits (not used for value calculation, but for uniqueness)
    enum Suit {
        Hearts,
        Diamonds,
        Clubs,
        Spades
    }

    /// @notice Card ranks (0-12 representing Ace through King)
    enum Rank {
        Ace,    // 0
        Two,    // 1
        Three,  // 2
        Four,   // 3
        Five,   // 4
        Six,    // 5
        Seven,  // 6
        Eight,  // 7
        Nine,   // 8
        Ten,    // 9
        Jack,   // 10
        Queen,  // 11
        King    // 12
    }

    /// @notice Game state
    enum GameState {
        Betting,        // Waiting for bet
        Dealing,        // Initial cards being dealt
        PlayerTurn,     // Player making decisions
        DealerTurn,     // Dealer revealing and playing
        Resolved        // Game complete
    }

    /// @notice Player actions
    enum Action {
        Hit,
        Stand,
        DoubleDown,
        Split,
        Insurance
    }

    /// @notice Hand outcome
    enum Outcome {
        Pending,
        PlayerBlackjack,    // Player wins 3:2
        DealerBlackjack,    // Dealer wins (unless push)
        PlayerWin,          // Player wins 1:1
        DealerWin,          // Dealer wins
        Push,               // Tie - bet returned
        PlayerBust,         // Player busted
        DealerBust          // Dealer busted
    }

    // ============ Structs ============

    /// @notice Represents a single card
    struct Card {
        uint8 id;       // 0-51 unique card identifier
        bool revealed;  // Whether card is face up
    }

    /// @notice Represents a hand of cards
    struct Hand {
        Card[] cards;
        uint256 bet;
        bool doubled;
        bool fromSplit;
        bool stood;
        bool busted;
        Outcome outcome;
    }

    /// @notice Full game state for a blackjack round
    struct BlackjackGame {
        Hand[] playerHands;     // Player can have multiple hands from splits
        Hand dealerHand;
        uint8 activeHandIndex;  // Which hand player is currently playing
        GameState state;
        bool insuranceTaken;
        uint256 insuranceBet;
        uint8 cardsDealt;       // Track how many cards dealt from randomness
    }

    // ============ Card Functions ============

    /// @notice Get card rank from card ID (0-51)
    /// @param cardId The card ID
    /// @return The rank (0-12)
    function getRank(uint8 cardId) internal pure returns (uint8) {
        return cardId % 13;
    }

    /// @notice Get card suit from card ID (0-51)
    /// @param cardId The card ID
    /// @return The suit (0-3)
    function getSuit(uint8 cardId) internal pure returns (uint8) {
        return cardId / 13;
    }

    /// @notice Get the point value of a card rank
    /// @param rank The card rank (0-12)
    /// @return value The point value (Ace=11, Face cards=10, others=rank+1)
    function getCardValue(uint8 rank) internal pure returns (uint8) {
        if (rank == 0) return 11;  // Ace (will be adjusted if needed)
        if (rank >= 9) return 10;  // 10, J, Q, K
        return rank + 1;           // 2-9
    }

    /// @notice Check if a rank is an Ace
    function isAce(uint8 rank) internal pure returns (bool) {
        return rank == 0;
    }

    // ============ Hand Calculation Functions ============

    /// @notice Calculate the best value of a hand
    /// @dev Handles Aces as 1 or 11 to get best non-bust value
    /// @param cards Array of cards in the hand
    /// @return value The hand value
    /// @return isSoft Whether the hand is soft (Ace counted as 11)
    function calculateHandValue(Card[] memory cards) internal pure returns (uint8 value, bool isSoft) {
        uint8 total = 0;
        uint8 aces = 0;

        for (uint8 i = 0; i < cards.length; i++) {
            if (!cards[i].revealed) continue;  // Skip hidden cards

            uint8 rank = getRank(cards[i].id);
            uint8 cardValue = getCardValue(rank);

            total += cardValue;
            if (isAce(rank)) {
                aces++;
            }
        }

        // Adjust Aces from 11 to 1 if necessary to avoid bust
        isSoft = aces > 0 && total <= BLACKJACK;
        while (total > BLACKJACK && aces > 0) {
            total -= 10;  // Convert Ace from 11 to 1
            aces--;
        }

        return (total, isSoft && total <= BLACKJACK);
    }

    /// @notice Calculate hand value including hidden cards (for dealer final play)
    function calculateFullHandValue(Card[] memory cards) internal pure returns (uint8 value, bool isSoft) {
        uint8 total = 0;
        uint8 aces = 0;

        for (uint8 i = 0; i < cards.length; i++) {
            uint8 rank = getRank(cards[i].id);
            uint8 cardValue = getCardValue(rank);

            total += cardValue;
            if (isAce(rank)) {
                aces++;
            }
        }

        isSoft = aces > 0 && total <= BLACKJACK;
        while (total > BLACKJACK && aces > 0) {
            total -= 10;
            aces--;
        }

        return (total, isSoft && total <= BLACKJACK);
    }

    /// @notice Check if a hand is a blackjack (Ace + 10-value card)
    function isBlackjack(Card[] memory cards) internal pure returns (bool) {
        if (cards.length != 2) return false;

        (uint8 value,) = calculateFullHandValue(cards);
        return value == BLACKJACK;
    }

    /// @notice Check if a hand is busted (over 21)
    function isBusted(Card[] memory cards) internal pure returns (bool) {
        (uint8 value,) = calculateFullHandValue(cards);
        return value > BLACKJACK;
    }

    /// @notice Check if two cards can be split (same rank)
    function canSplit(Card[] memory cards) internal pure returns (bool) {
        if (cards.length != 2) return false;

        uint8 rank1 = getRank(cards[0].id);
        uint8 rank2 = getRank(cards[1].id);

        // 10-value cards can be split with each other (10, J, Q, K)
        if (rank1 >= 9 && rank2 >= 9) return true;

        return rank1 == rank2;
    }

    /// @notice Check if a hand can double down (typically only on first two cards)
    function canDoubleDown(Hand memory hand) internal pure returns (bool) {
        return hand.cards.length == 2 && !hand.doubled && !hand.stood && !hand.busted;
    }

    // ============ Game Logic Functions ============

    /// @notice Generate a card from a random word, avoiding duplicates
    /// @param randomWord The random value
    /// @param usedCards Bitmap of already dealt cards
    /// @return cardId The generated card ID
    /// @return newUsedCards Updated bitmap
    function generateCard(uint256 randomWord, uint256 usedCards)
        internal
        pure
        returns (uint8 cardId, uint256 newUsedCards)
    {
        // Find an unused card
        uint8 attempts = 0;
        uint8 candidate;

        do {
            candidate = uint8((randomWord >> (attempts * 8)) % DECK_SIZE);
            attempts++;

            // If we've tried many times, do linear search for next available
            if (attempts > 6) {
                for (uint8 i = 0; i < DECK_SIZE; i++) {
                    uint8 idx = (candidate + i) % DECK_SIZE;
                    if ((usedCards & (1 << idx)) == 0) {
                        candidate = idx;
                        break;
                    }
                }
                break;
            }
        } while ((usedCards & (1 << candidate)) != 0);

        // Mark card as used
        newUsedCards = usedCards | (1 << candidate);
        return (candidate, newUsedCards);
    }

    /// @notice Calculate payout multiplier for an outcome
    /// @param outcome The hand outcome
    /// @return numerator Payout numerator
    /// @return denominator Payout denominator
    function getPayoutMultiplier(Outcome outcome) internal pure returns (uint256 numerator, uint256 denominator) {
        if (outcome == Outcome.PlayerBlackjack) {
            return (3, 2);  // 3:2 payout
        } else if (outcome == Outcome.PlayerWin || outcome == Outcome.DealerBust) {
            return (1, 1);  // 1:1 payout
        } else if (outcome == Outcome.Push) {
            return (0, 1);  // Return bet only (no profit)
        } else {
            return (0, 0);  // Loss - no payout
        }
    }

    /// @notice Calculate total payout for a hand
    /// @param bet The original bet amount
    /// @param outcome The hand outcome
    /// @param doubled Whether the bet was doubled
    /// @return payout Total payout (0 if loss)
    function calculatePayout(uint256 bet, Outcome outcome, bool doubled)
        internal
        pure
        returns (uint256 payout)
    {
        uint256 effectiveBet = doubled ? bet * 2 : bet;

        (uint256 num, uint256 denom) = getPayoutMultiplier(outcome);

        if (denom == 0) {
            return 0;  // Loss
        }

        if (outcome == Outcome.Push) {
            return effectiveBet;  // Return original bet
        }

        // Payout = bet + (bet * multiplier)
        return effectiveBet + (effectiveBet * num / denom);
    }

    /// @notice Calculate insurance payout (2:1 if dealer has blackjack)
    function calculateInsurancePayout(uint256 insuranceBet, bool dealerHasBlackjack)
        internal
        pure
        returns (uint256)
    {
        if (dealerHasBlackjack) {
            return insuranceBet * 3;  // 2:1 plus original bet
        }
        return 0;  // Insurance lost
    }

    /// @notice Determine the outcome of a hand
    /// @param playerValue Player's hand value
    /// @param dealerValue Dealer's hand value
    /// @param playerBlackjack Whether player has blackjack
    /// @param dealerBlackjack Whether dealer has blackjack
    /// @param playerBusted Whether player busted
    /// @param dealerBusted Whether dealer busted
    /// @return outcome The hand outcome
    function determineOutcome(
        uint8 playerValue,
        uint8 dealerValue,
        bool playerBlackjack,
        bool dealerBlackjack,
        bool playerBusted,
        bool dealerBusted
    ) internal pure returns (Outcome outcome) {
        // Player bust always loses (even if dealer busts)
        if (playerBusted) {
            return Outcome.PlayerBust;
        }

        // Blackjack outcomes
        if (playerBlackjack && dealerBlackjack) {
            return Outcome.Push;
        }
        if (playerBlackjack) {
            return Outcome.PlayerBlackjack;
        }
        if (dealerBlackjack) {
            return Outcome.DealerBlackjack;
        }

        // Dealer bust (player didn't bust)
        if (dealerBusted) {
            return Outcome.DealerBust;
        }

        // Compare values
        if (playerValue > dealerValue) {
            return Outcome.PlayerWin;
        } else if (dealerValue > playerValue) {
            return Outcome.DealerWin;
        } else {
            return Outcome.Push;
        }
    }

    /// @notice Check if dealer should hit
    /// @dev Dealer hits on soft 17 in this implementation (Vegas rules)
    function dealerShouldHit(uint8 value, bool isSoft) internal pure returns (bool) {
        if (value < DEALER_STAND) return true;
        // Hit on soft 17 (common Vegas rule)
        if (value == DEALER_STAND && isSoft) return true;
        return false;
    }

    /// @notice Check if dealer's upcard is an Ace (for insurance)
    function dealerShowsAce(Card[] memory dealerCards) internal pure returns (bool) {
        if (dealerCards.length == 0) return false;
        // First card is typically the upcard
        uint8 rank = getRank(dealerCards[0].id);
        return isAce(rank);
    }

    /// @notice Check if dealer's upcard is a 10-value card
    function dealerShowsTen(Card[] memory dealerCards) internal pure returns (bool) {
        if (dealerCards.length == 0) return false;
        uint8 rank = getRank(dealerCards[0].id);
        return rank >= 9;  // 10, J, Q, K
    }

    // ============ Validation Functions ============

    /// @notice Validate if an action is allowed in current state
    function validateAction(
        Hand memory hand,
        Action action,
        GameState state,
        uint8 numHands
    ) internal pure returns (bool) {
        if (state != GameState.PlayerTurn) return false;
        if (hand.stood || hand.busted) return false;

        if (action == Action.Hit) {
            return true;  // Can always hit if not stood/busted
        }

        if (action == Action.Stand) {
            return true;  // Can always stand
        }

        if (action == Action.DoubleDown) {
            return canDoubleDown(hand);
        }

        if (action == Action.Split) {
            // Can split if first two cards match and haven't exceeded max splits
            return hand.cards.length == 2 &&
                   canSplit(hand.cards) &&
                   numHands < MAX_SPLITS + 1;
        }

        return false;
    }

    /// @notice Check if all player hands are complete
    function allHandsComplete(Hand[] memory hands) internal pure returns (bool) {
        for (uint8 i = 0; i < hands.length; i++) {
            if (!hands[i].stood && !hands[i].busted) {
                return false;
            }
        }
        return true;
    }

    // ============ Card String Functions (for events/debugging) ============

    /// @notice Get rank name for a card
    function getRankName(uint8 rank) internal pure returns (string memory) {
        if (rank == 0) return "A";
        if (rank == 1) return "2";
        if (rank == 2) return "3";
        if (rank == 3) return "4";
        if (rank == 4) return "5";
        if (rank == 5) return "6";
        if (rank == 6) return "7";
        if (rank == 7) return "8";
        if (rank == 8) return "9";
        if (rank == 9) return "10";
        if (rank == 10) return "J";
        if (rank == 11) return "Q";
        return "K";
    }

    /// @notice Get suit name for a card
    function getSuitName(uint8 suit) internal pure returns (string memory) {
        if (suit == 0) return "Hearts";
        if (suit == 1) return "Diamonds";
        if (suit == 2) return "Clubs";
        return "Spades";
    }
}
