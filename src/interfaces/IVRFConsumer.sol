// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVRFConsumer - Interface for VRF Consumer
/// @notice Defines the interface for requesting and receiving randomness
/// @dev Implemented by VRFConsumer.sol
interface IVRFConsumer {
    /// @notice VRF request details
    struct VRFRequest {
        address game;
        uint256 betId;
        uint64 timestamp;
        bool fulfilled;
    }

    // ============ Events ============

    /// @notice Emitted when randomness is requested
    event RandomnessRequested(
        uint256 indexed requestId, address indexed game, uint256 indexed betId, uint32 numWords
    );

    /// @notice Emitted when randomness is fulfilled
    event RandomnessFulfilled(uint256 indexed requestId, address indexed game, uint256 indexed betId);

    // ============ Functions ============

    /// @notice Request randomness for a bet
    /// @param game The game contract requesting randomness
    /// @param betId The bet ID to resolve
    /// @return requestId The VRF request ID
    function requestRandomness(address game, uint256 betId) external returns (uint256 requestId);

    /// @notice Get request details
    /// @param requestId The request ID
    /// @return The VRF request struct
    function getRequest(uint256 requestId) external view returns (VRFRequest memory);

    /// @notice Get request ID for a game bet
    /// @param game The game address
    /// @param betId The bet ID
    /// @return The request ID (0 if none)
    function getRequestId(address game, uint256 betId) external view returns (uint256);

    /// @notice Check if a request is pending
    /// @param requestId The request ID
    /// @return True if pending (not fulfilled)
    function isPending(uint256 requestId) external view returns (bool);

    /// @notice Get VRF statistics
    /// @return requests Total requests
    /// @return fulfilled Total fulfilled
    /// @return pending Total pending
    function getStats() external view returns (uint256 requests, uint256 fulfilled, uint256 pending);
}
