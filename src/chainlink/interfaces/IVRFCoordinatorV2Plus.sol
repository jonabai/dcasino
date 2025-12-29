// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVRFCoordinatorV2Plus - Chainlink VRF V2.5 Coordinator Interface
/// @notice Interface for requesting and receiving verifiable randomness
/// @dev Based on Chainlink VRF V2.5 (V2 Plus) specification
interface IVRFCoordinatorV2Plus {
    /// @notice Request random words
    /// @param req The randomness request parameters
    /// @return requestId The unique ID for this request
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId);

    /// @notice Get subscription details
    /// @param subId The subscription ID
    /// @return balance The subscription balance
    /// @return reqCount The number of requests made
    /// @return owner The subscription owner
    /// @return consumers The list of consumer addresses
    function getSubscription(uint256 subId)
        external
        view
        returns (uint96 balance, uint96 reqCount, address owner, address[] memory consumers);

    /// @notice Add a consumer to a subscription
    /// @param subId The subscription ID
    /// @param consumer The consumer address to add
    function addConsumer(uint256 subId, address consumer) external;

    /// @notice Remove a consumer from a subscription
    /// @param subId The subscription ID
    /// @param consumer The consumer address to remove
    function removeConsumer(uint256 subId, address consumer) external;

    /// @notice Create a new subscription
    /// @return subId The new subscription ID
    function createSubscription() external returns (uint256 subId);

    /// @notice Cancel a subscription
    /// @param subId The subscription ID
    /// @param to The address to send remaining funds to
    function cancelSubscription(uint256 subId, address to) external;

    /// @notice Check if pending request exists
    /// @param subId The subscription ID
    /// @param consumer The consumer address
    /// @return Whether a pending request exists
    function pendingRequestExists(uint256 subId, address consumer) external view returns (bool);
}

/// @title VRFV2PlusClient - VRF V2.5 Client Library
/// @notice Provides helper structures for VRF V2.5 requests
library VRFV2PlusClient {
    /// @notice Extra arguments structure for VRF requests
    struct ExtraArgsV1 {
        bool nativePayment;
    }

    /// @notice Random words request structure
    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    /// @notice Compute extra args bytes
    /// @param extraArgs The extra arguments
    /// @return The encoded extra args
    function _argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encode(extraArgs.nativePayment);
    }

    /// @notice Tag for extra args version 1
    bytes4 public constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    /// @notice Encode extra args with tag
    /// @param extraArgs The extra arguments to encode
    /// @return The tagged encoded bytes
    function extraArgsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory) {
        return bytes.concat(EXTRA_ARGS_V1_TAG, _argsToBytes(extraArgs));
    }
}
