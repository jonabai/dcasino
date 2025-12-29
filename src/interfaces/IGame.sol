// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BetLib} from "../libraries/BetLib.sol";

/// @title IGame - Interface for Casino Games
/// @notice Defines the standard interface that all casino games must implement
/// @dev Implemented by game contracts (Roulette, Blackjack, etc.)
interface IGame {
    // ============ Events ============

    /// @notice Emitted when a bet is placed
    /// @param betId Unique identifier for the bet
    /// @param player Address of the player
    /// @param amount Amount wagered
    /// @param betData Game-specific bet parameters
    event BetPlaced(uint256 indexed betId, address indexed player, uint256 amount, bytes betData);

    /// @notice Emitted when a bet is resolved
    /// @param betId Unique identifier for the bet
    /// @param player Address of the player
    /// @param payout Payout amount (0 if lost)
    /// @param won Whether the bet was won
    event BetResolved(uint256 indexed betId, address indexed player, uint256 payout, bool won);

    /// @notice Emitted when a bet is cancelled
    /// @param betId Unique identifier for the bet
    /// @param player Address of the player
    event BetCancelled(uint256 indexed betId, address indexed player);

    /// @notice Emitted when randomness is requested for a bet
    /// @param betId The bet ID
    /// @param requestId The VRF request ID
    event RandomnessRequested(uint256 indexed betId, uint256 indexed requestId);

    // ============ View Functions ============

    /// @notice Returns the unique game identifier
    /// @return The game ID as bytes32
    function gameId() external view returns (bytes32);

    /// @notice Returns the human-readable game name
    /// @return The game name
    function gameName() external view returns (string memory);

    /// @notice Returns the casino contract address
    /// @return The casino address
    function casino() external view returns (address);

    /// @notice Returns the treasury contract address
    /// @return The treasury address
    function treasury() external view returns (address);

    /// @notice Returns the game registry contract address
    /// @return The registry address
    function gameRegistry() external view returns (address);

    /// @notice Returns the minimum bet amount for this game
    /// @return Minimum bet in wei
    function getMinBet() external view returns (uint256);

    /// @notice Returns the maximum bet amount for this game
    /// @return Maximum bet in wei
    function getMaxBet() external view returns (uint256);

    /// @notice Returns whether the game is currently active
    /// @return True if the game is active
    function isActive() external view returns (bool);

    /// @notice Returns the house edge for this game in basis points
    /// @return House edge (270 = 2.7% for European roulette)
    function getHouseEdge() external pure returns (uint256);

    /// @notice Gets bet information by ID
    /// @param betId The bet identifier
    /// @return bet The bet struct
    function getBet(uint256 betId) external view returns (BetLib.Bet memory bet);

    /// @notice Gets all bet IDs for a player
    /// @param player The player address
    /// @return Array of bet IDs
    function getPlayerBets(address player) external view returns (uint256[] memory);

    /// @notice Gets all pending bet IDs
    /// @return Array of pending bet IDs
    function getPendingBets() external view returns (uint256[] memory);

    /// @notice Gets the count of pending bets
    /// @return Number of pending bets
    function getPendingBetCount() external view returns (uint256);

    // ============ Player Functions ============

    /// @notice Places a bet on the game
    /// @param betData Game-specific bet parameters (encoded)
    /// @return betId The unique identifier for the placed bet
    function placeBet(bytes calldata betData) external payable returns (uint256 betId);

    /// @notice Cancels a pending bet (if allowed)
    /// @param betId The bet to cancel
    function cancelBet(uint256 betId) external;

    // ============ Resolution Functions ============

    /// @notice Resolves a bet with the provided random words
    /// @dev Called by VRF consumer or automation
    /// @param betId The bet to resolve
    /// @param randomWords Array of random values from VRF
    function resolveBet(uint256 betId, uint256[] calldata randomWords) external;

    /// @notice Requests resolution for a pending bet
    /// @dev Triggers VRF request if needed
    /// @param betId The bet to resolve
    function requestResolution(uint256 betId) external;

    // ============ Admin Functions ============

    /// @notice Pauses the game
    function pause() external;

    /// @notice Unpauses the game
    function unpause() external;

    /// @notice Sets the minimum bet amount
    /// @param newMinBet New minimum bet in wei
    function setMinBet(uint256 newMinBet) external;

    /// @notice Sets the maximum bet amount
    /// @param newMaxBet New maximum bet in wei
    function setMaxBet(uint256 newMaxBet) external;
}
