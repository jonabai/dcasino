// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "./Errors.sol";

/// @title BetLib - Bet structures and validation utilities
/// @notice Provides common bet-related structures and validation functions
/// @dev Used by all game contracts for consistent bet handling
library BetLib {
    // ============ Constants ============

    /// @notice Basis points denominator (100% = 10000)
    uint256 internal constant BASIS_POINTS = 10_000;

    // ============ Enums ============

    /// @notice Status of a bet
    enum BetStatus {
        Pending, // Bet placed, waiting for resolution
        Won, // Bet won, payout processed
        Lost, // Bet lost
        Cancelled, // Bet cancelled, refunded
        Expired // Bet expired without resolution

    }

    // ============ Structs ============

    /// @notice Core bet information
    /// @param id Unique identifier for the bet
    /// @param player Address of the player who placed the bet
    /// @param amount Amount wagered in wei
    /// @param potentialPayout Maximum potential payout for this bet
    /// @param actualPayout Actual payout amount (set after resolution)
    /// @param timestamp When the bet was placed
    /// @param status Current status of the bet
    /// @param data Game-specific bet data (encoded parameters)
    struct Bet {
        uint256 id;
        address player;
        uint256 amount;
        uint256 potentialPayout;
        uint256 actualPayout;
        uint64 timestamp;
        BetStatus status;
        bytes data;
    }

    /// @notice Bet limits configuration
    /// @param minBet Minimum bet amount in wei
    /// @param maxBet Maximum bet amount in wei
    /// @param maxBetsPerPlayer Maximum number of active bets per player
    /// @param maxBetsPerRound Maximum total bets per round
    struct BetLimits {
        uint256 minBet;
        uint256 maxBet;
        uint256 maxBetsPerPlayer;
        uint256 maxBetsPerRound;
    }

    /// @notice Round information for batch betting games
    /// @param id Round identifier
    /// @param startTime When the round started
    /// @param endTime When the round ends/ended
    /// @param isActive Whether the round is accepting bets
    /// @param isResolved Whether the round has been resolved
    /// @param totalBets Total number of bets in the round
    /// @param totalAmount Total amount wagered in the round
    /// @param result The result of the round (game-specific encoding)
    struct Round {
        uint256 id;
        uint64 startTime;
        uint64 endTime;
        bool isActive;
        bool isResolved;
        uint256 totalBets;
        uint256 totalAmount;
        bytes result;
    }

    // ============ Validation Functions ============

    /// @notice Validates a bet amount against limits
    /// @param amount The bet amount to validate
    /// @param minBet Minimum allowed bet
    /// @param maxBet Maximum allowed bet
    function validateBetAmount(uint256 amount, uint256 minBet, uint256 maxBet) internal pure {
        if (amount < minBet) {
            revert Errors.BetTooSmall(amount, minBet);
        }
        if (amount > maxBet) {
            revert Errors.BetTooLarge(amount, maxBet);
        }
    }

    /// @notice Validates bet limits configuration
    /// @param limits The bet limits to validate
    function validateBetLimits(BetLimits memory limits) internal pure {
        if (limits.minBet == 0) {
            revert Errors.InvalidAmount();
        }
        if (limits.minBet > limits.maxBet) {
            revert Errors.MinBetExceedsMaxBet();
        }
    }

    /// @notice Checks if a bet can be cancelled
    /// @param bet The bet to check
    /// @return canCancel True if the bet can be cancelled
    function canCancel(Bet memory bet) internal pure returns (bool) {
        // Only pending bets can be cancelled
        return bet.status == BetStatus.Pending;
    }

    /// @notice Checks if a bet is resolved
    /// @param bet The bet to check
    /// @return isResolved True if the bet has been resolved
    function isResolved(Bet memory bet) internal pure returns (bool) {
        return bet.status == BetStatus.Won || bet.status == BetStatus.Lost || bet.status == BetStatus.Cancelled
            || bet.status == BetStatus.Expired;
    }

    /// @notice Creates a new bet struct
    /// @param id Bet identifier
    /// @param player Player address
    /// @param amount Bet amount
    /// @param potentialPayout Maximum potential payout
    /// @param data Game-specific bet data
    /// @return bet The created bet struct
    function createBet(uint256 id, address player, uint256 amount, uint256 potentialPayout, bytes memory data)
        internal
        view
        returns (Bet memory bet)
    {
        return Bet({
            id: id,
            player: player,
            amount: amount,
            potentialPayout: potentialPayout,
            actualPayout: 0,
            timestamp: uint64(block.timestamp),
            status: BetStatus.Pending,
            data: data
        });
    }

    /// @notice Marks a bet as won
    /// @param bet The bet to update
    /// @param payout The payout amount
    function markAsWon(Bet storage bet, uint256 payout) internal {
        bet.status = BetStatus.Won;
        bet.actualPayout = payout;
    }

    /// @notice Marks a bet as lost
    /// @param bet The bet to update
    function markAsLost(Bet storage bet) internal {
        bet.status = BetStatus.Lost;
        bet.actualPayout = 0;
    }

    /// @notice Marks a bet as cancelled
    /// @param bet The bet to update
    function markAsCancelled(Bet storage bet) internal {
        if (!canCancel(Bet({
            id: bet.id,
            player: bet.player,
            amount: bet.amount,
            potentialPayout: bet.potentialPayout,
            actualPayout: bet.actualPayout,
            timestamp: bet.timestamp,
            status: bet.status,
            data: bet.data
        }))) {
            revert Errors.BetCannotBeCancelled(bet.id);
        }
        bet.status = BetStatus.Cancelled;
        bet.actualPayout = bet.amount; // Refund the original amount
    }
}
