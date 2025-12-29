// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Errors - Custom error definitions for the Casino ecosystem
/// @notice Gas-efficient custom errors used across all casino contracts
/// @dev Custom errors are more gas efficient than require strings
library Errors {
    // ============ Access Control Errors ============

    /// @notice Thrown when caller is not authorized to perform an action
    error Unauthorized();

    /// @notice Thrown when caller lacks the required role
    /// @param account The account that lacks the role
    /// @param role The required role
    error MissingRole(address account, bytes32 role);

    // ============ Address Validation Errors ============

    /// @notice Thrown when an invalid address (zero address) is provided
    error InvalidAddress();

    /// @notice Thrown when a game address is invalid
    error InvalidGameAddress();

    /// @notice Thrown when a player address is invalid
    error InvalidPlayerAddress();

    // ============ Amount Validation Errors ============

    /// @notice Thrown when an amount is invalid (zero or negative)
    error InvalidAmount();

    /// @notice Thrown when a bet amount is below the minimum
    /// @param amount The bet amount
    /// @param minBet The minimum allowed bet
    error BetTooSmall(uint256 amount, uint256 minBet);

    /// @notice Thrown when a bet amount exceeds the maximum
    /// @param amount The bet amount
    /// @param maxBet The maximum allowed bet
    error BetTooLarge(uint256 amount, uint256 maxBet);

    /// @notice Thrown when a percentage value exceeds 100% (10000 basis points)
    error InvalidPercentage();

    // ============ Balance Errors ============

    /// @notice Thrown when there's insufficient balance for an operation
    error InsufficientBalance();

    /// @notice Thrown when the treasury doesn't have enough funds to cover a payout
    error InsufficientTreasuryBalance();

    /// @notice Thrown when trying to reserve more funds than available
    error InsufficientAvailableFunds();

    /// @notice Thrown when trying to release more funds than reserved
    error InsufficientReservedFunds();

    // ============ Game Errors ============

    /// @notice Thrown when a game is not registered in the registry
    error GameNotRegistered();

    /// @notice Thrown when trying to register a game that's already registered
    error GameAlreadyRegistered();

    /// @notice Thrown when a game is not active
    error GameNotActive();

    /// @notice Thrown when a game doesn't implement the required interface
    error GameDoesNotImplementInterface();

    // ============ Bet Errors ============

    /// @notice Thrown when a bet is not found
    /// @param betId The ID of the bet that wasn't found
    error BetNotFound(uint256 betId);

    /// @notice Thrown when trying to resolve a bet that's already resolved
    /// @param betId The ID of the already resolved bet
    error BetAlreadyResolved(uint256 betId);

    /// @notice Thrown when trying to cancel a bet that cannot be cancelled
    /// @param betId The ID of the bet
    error BetCannotBeCancelled(uint256 betId);

    /// @notice Thrown when bet parameters are invalid
    error InvalidBetParameters();

    /// @notice Thrown when trying to place a bet on an inactive round
    error RoundNotActive();

    /// @notice Thrown when a round is not found
    error RoundNotFound();

    // ============ Transfer Errors ============

    /// @notice Thrown when an ETH transfer fails
    error TransferFailed();

    /// @notice Thrown when a payout transfer fails
    /// @param player The player who should receive the payout
    /// @param amount The amount that failed to transfer
    error PayoutFailed(address player, uint256 amount);

    // ============ State Errors ============

    /// @notice Thrown when the contract is paused
    error ContractPaused();

    /// @notice Thrown when the contract is not paused but should be
    error ContractNotPaused();

    /// @notice Thrown when an operation is attempted in an invalid state
    error InvalidState();

    // ============ VRF Errors ============

    /// @notice Thrown when a VRF request is not found
    error VRFRequestNotFound();

    /// @notice Thrown when a VRF request has already been fulfilled
    error VRFRequestAlreadyFulfilled();

    /// @notice Thrown when the VRF callback caller is not authorized
    error InvalidVRFCaller();

    // ============ Configuration Errors ============

    /// @notice Thrown when min bet is greater than max bet
    error MinBetExceedsMaxBet();

    /// @notice Thrown when max payout ratio is invalid
    error InvalidMaxPayoutRatio();

    /// @notice Thrown when the fee percentage is too high
    error FeeTooHigh();
}
