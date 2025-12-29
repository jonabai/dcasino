// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGameRegistry - Interface for the Game Registry
/// @notice Defines the interface for registering and managing casino games
/// @dev Implemented by GameRegistry.sol
interface IGameRegistry {
    // ============ Structs ============

    /// @notice Information about a registered game
    /// @param gameAddress Address of the game contract
    /// @param gameId Unique identifier for the game
    /// @param name Human-readable name of the game
    /// @param isActive Whether the game is currently active
    /// @param registeredAt Timestamp when the game was registered
    /// @param totalBetsPlaced Total number of bets placed on this game
    /// @param totalVolume Total volume wagered on this game
    struct GameInfo {
        address gameAddress;
        bytes32 gameId;
        string name;
        bool isActive;
        uint256 registeredAt;
        uint256 totalBetsPlaced;
        uint256 totalVolume;
    }

    // ============ Events ============

    /// @notice Emitted when a new game is registered
    /// @param game Address of the game contract
    /// @param gameId Unique identifier assigned to the game
    /// @param name Name of the game
    event GameRegistered(address indexed game, bytes32 indexed gameId, string name);

    /// @notice Emitted when a game is deregistered
    /// @param game Address of the game contract
    /// @param gameId Unique identifier of the game
    event GameDeregistered(address indexed game, bytes32 indexed gameId);

    /// @notice Emitted when a game is enabled
    /// @param game Address of the game contract
    event GameEnabled(address indexed game);

    /// @notice Emitted when a game is disabled
    /// @param game Address of the game contract
    event GameDisabled(address indexed game);

    /// @notice Emitted when a bet is recorded for statistics
    /// @param game Address of the game contract
    /// @param amount Amount of the bet
    event BetRecorded(address indexed game, uint256 amount);

    // ============ View Functions ============

    /// @notice Checks if a game address is registered
    /// @param game Address to check
    /// @return True if the game is registered
    function isRegisteredGame(address game) external view returns (bool);

    /// @notice Checks if a game is currently active
    /// @param game Address to check
    /// @return True if the game is active
    function isActiveGame(address game) external view returns (bool);

    /// @notice Gets game info by game ID
    /// @param gameId The unique game identifier
    /// @return info The game information struct
    function getGame(bytes32 gameId) external view returns (GameInfo memory info);

    /// @notice Gets game info by game address
    /// @param game The game contract address
    /// @return info The game information struct
    function getGameByAddress(address game) external view returns (GameInfo memory info);

    /// @notice Gets all registered game addresses
    /// @return Array of game addresses
    function getAllGames() external view returns (address[] memory);

    /// @notice Gets all active game addresses
    /// @return Array of active game addresses
    function getActiveGames() external view returns (address[] memory);

    /// @notice Gets the total number of registered games
    /// @return Number of registered games
    function gameCount() external view returns (uint256);

    /// @notice Gets the game ID for a game address
    /// @param game The game contract address
    /// @return gameId The unique game identifier
    function getGameId(address game) external view returns (bytes32 gameId);

    // ============ State-Changing Functions ============

    /// @notice Registers a new game
    /// @param game Address of the game contract
    /// @param name Human-readable name for the game
    /// @return gameId The unique identifier assigned to the game
    function registerGame(address game, string calldata name) external returns (bytes32 gameId);

    /// @notice Deregisters an existing game
    /// @param game Address of the game to deregister
    function deregisterGame(address game) external;

    /// @notice Enables a registered game
    /// @param game Address of the game to enable
    function enableGame(address game) external;

    /// @notice Disables a registered game
    /// @param game Address of the game to disable
    function disableGame(address game) external;

    /// @notice Records a bet for statistics tracking
    /// @dev Called by games when a bet is placed
    /// @param game Address of the game
    /// @param amount Amount of the bet
    function recordBet(address game, uint256 amount) external;
}
