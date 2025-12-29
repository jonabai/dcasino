// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "./interfaces/IVRFCoordinatorV2Plus.sol";

/// @title VRFConsumerBaseV2Plus - Abstract base for VRF V2.5 consumers
/// @notice Base contract for contracts that need verifiable randomness
/// @dev Inherit this contract and implement rawFulfillRandomWords
abstract contract VRFConsumerBaseV2Plus {
    /// @notice Error when caller is not the VRF coordinator
    error OnlyCoordinatorCanFulfill(address have, address want);

    /// @notice The VRF Coordinator contract
    IVRFCoordinatorV2Plus internal immutable i_vrfCoordinator;

    /// @notice Initialize the VRF consumer
    /// @param coordinator The VRF Coordinator address
    constructor(address coordinator) {
        i_vrfCoordinator = IVRFCoordinatorV2Plus(coordinator);
    }

    /// @notice Callback function for VRF coordinator
    /// @dev Only callable by the VRF coordinator
    /// @param requestId The request ID
    /// @param randomWords The random values
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(i_vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(i_vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /// @notice Handle the random words callback
    /// @dev Override this function to process random words
    /// @param requestId The request ID
    /// @param randomWords The random values
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;

    /// @notice Get the VRF coordinator address
    /// @return The coordinator address
    function getVRFCoordinator() public view returns (address) {
        return address(i_vrfCoordinator);
    }
}
