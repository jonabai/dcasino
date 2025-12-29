// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AutomationCompatibleInterface - Chainlink Automation Interface
/// @notice Interface for Chainlink Automation compatible contracts
/// @dev Implement checkUpkeep and performUpkeep for automation
interface AutomationCompatibleInterface {
    /// @notice Check if upkeep is needed
    /// @dev Called off-chain by Automation nodes
    /// @param checkData Data passed to checkUpkeep (can be used for filtering)
    /// @return upkeepNeeded True if performUpkeep should be called
    /// @return performData Data to pass to performUpkeep
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData);

    /// @notice Perform the upkeep
    /// @dev Called on-chain when checkUpkeep returns true
    /// @param performData Data returned by checkUpkeep
    function performUpkeep(bytes calldata performData) external;
}

/// @title StreamsLookupCompatibleInterface - Chainlink Data Streams Interface
/// @notice Interface for contracts using Chainlink Data Streams
/// @dev Optional - for advanced use cases with real-time data
interface StreamsLookupCompatibleInterface {
    /// @notice Error to trigger streams lookup
    error StreamsLookup(
        string feedParamKey,
        string[] feeds,
        string timeParamKey,
        uint256 time,
        bytes extraData
    );

    /// @notice Callback for streams lookup
    /// @param values The feed values
    /// @param extraData Extra data from the lookup
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData Data for performUpkeep
    function checkCallback(bytes[] memory values, bytes memory extraData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData);
}
