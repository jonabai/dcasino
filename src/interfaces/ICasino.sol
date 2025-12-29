// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICasino - Interface for the Main Casino Contract
/// @notice Defines the interface for the main casino registry and admin functions
/// @dev Implemented by Casino.sol
interface ICasino {
    // ============ Events ============

    /// @notice Emitted when the casino is paused
    /// @param by Address that triggered the pause
    event CasinoPaused(address indexed by);

    /// @notice Emitted when the casino is unpaused
    /// @param by Address that triggered the unpause
    event CasinoUnpaused(address indexed by);

    /// @notice Emitted when the treasury address is updated
    /// @param oldTreasury Previous treasury address
    /// @param newTreasury New treasury address
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when the game registry address is updated
    /// @param oldRegistry Previous registry address
    /// @param newRegistry New registry address
    event GameRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when an emergency withdrawal is performed
    /// @param token Token address (address(0) for ETH)
    /// @param to Recipient address
    /// @param amount Amount withdrawn
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);

    // ============ View Functions ============

    /// @notice Returns the treasury contract address
    /// @return The treasury address
    function treasury() external view returns (address);

    /// @notice Returns the game registry contract address
    /// @return The registry address
    function gameRegistry() external view returns (address);

    /// @notice Returns whether the casino is paused
    /// @return True if paused
    function isPaused() external view returns (bool);

    /// @notice Returns the casino version string
    /// @return Version string
    function version() external pure returns (string memory);

    // ============ Admin Functions ============

    /// @notice Pauses all casino operations
    function pause() external;

    /// @notice Resumes casino operations
    function unpause() external;

    /// @notice Updates the treasury contract address
    /// @param newTreasury New treasury address
    function setTreasury(address newTreasury) external;

    /// @notice Updates the game registry contract address
    /// @param newRegistry New registry address
    function setGameRegistry(address newRegistry) external;

    /// @notice Emergency withdrawal of ETH
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdrawETH(address to, uint256 amount) external;

    /// @notice Emergency withdrawal of ERC20 tokens
    /// @param token Token contract address
    /// @param to Recipient address
    /// @param amount Amount to withdraw
    function emergencyWithdrawToken(address token, address to, uint256 amount) external;
}
