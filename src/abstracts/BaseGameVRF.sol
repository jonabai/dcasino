// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseGame} from "./BaseGame.sol";
import {IVRFConsumer} from "../interfaces/IVRFConsumer.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title BaseGameVRF - Abstract Base Contract with VRF Integration
/// @notice Extends BaseGame with Chainlink VRF integration for randomness
/// @dev Games requiring VRF should inherit from this contract
abstract contract BaseGameVRF is BaseGame {
    // ============ Storage ============

    /// @notice VRF Consumer contract reference
    IVRFConsumer internal _vrfConsumer;

    /// @notice Mapping from VRF request ID to bet ID
    mapping(uint256 => uint256) internal _requestToBetId;

    /// @notice Mapping from bet ID to VRF request ID
    mapping(uint256 => uint256) internal _betToRequestId;

    /// @notice Whether VRF is enabled (allows fallback to manual resolution)
    bool internal _vrfEnabled;

    /// @notice Storage gap for future upgrades
    uint256[37] private __gap_vrf;

    // ============ Events ============

    /// @notice Emitted when VRF consumer is updated
    event VRFConsumerUpdated(address indexed oldConsumer, address indexed newConsumer);

    /// @notice Emitted when VRF is enabled/disabled
    event VRFEnabledUpdated(bool enabled);

    // ============ Initializer ============

    /// @notice Initializes the VRF-enabled base game contract
    /// @param admin Address to grant admin role
    /// @param name Human-readable game name
    /// @param casinoAddress Address of the casino contract
    /// @param treasuryAddress Address of the treasury contract
    /// @param registryAddress Address of the game registry contract
    /// @param vrfConsumerAddress Address of the VRF consumer contract
    function __BaseGameVRF_init(
        address admin,
        string memory name,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress,
        address vrfConsumerAddress
    ) internal onlyInitializing {
        __BaseGame_init(admin, name, casinoAddress, treasuryAddress, registryAddress);

        if (vrfConsumerAddress != address(0)) {
            _vrfConsumer = IVRFConsumer(vrfConsumerAddress);
            _vrfEnabled = true;
        }
    }

    // ============ View Functions ============

    /// @notice Get the VRF consumer address
    /// @return The VRF consumer address
    function vrfConsumer() external view returns (address) {
        return address(_vrfConsumer);
    }

    /// @notice Check if VRF is enabled
    /// @return True if VRF is enabled
    function isVRFEnabled() external view returns (bool) {
        return _vrfEnabled;
    }

    /// @notice Get the VRF request ID for a bet
    /// @param betId The bet ID
    /// @return The VRF request ID (0 if none)
    function getVRFRequestId(uint256 betId) external view returns (uint256) {
        return _betToRequestId[betId];
    }

    /// @notice Get the bet ID for a VRF request
    /// @param requestId The VRF request ID
    /// @return The bet ID (0 if none)
    function getBetIdFromRequest(uint256 requestId) external view returns (uint256) {
        return _requestToBetId[requestId];
    }

    // ============ Admin Functions ============

    /// @notice Set the VRF consumer address
    /// @param newVRFConsumer The new VRF consumer address
    function setVRFConsumer(address newVRFConsumer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldConsumer = address(_vrfConsumer);
        _vrfConsumer = IVRFConsumer(newVRFConsumer);
        emit VRFConsumerUpdated(oldConsumer, newVRFConsumer);
    }

    /// @notice Enable or disable VRF
    /// @param enabled Whether VRF should be enabled
    function setVRFEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (enabled && address(_vrfConsumer) == address(0)) {
            revert Errors.InvalidAddress();
        }
        _vrfEnabled = enabled;
        emit VRFEnabledUpdated(enabled);
    }

    // ============ Internal Functions ============

    /// @notice Requests randomness for bet resolution via VRF Consumer
    /// @dev Overrides BaseGame._requestRandomness
    /// @param betId The bet ID
    function _requestRandomness(uint256 betId) internal virtual override {
        if (_vrfEnabled && address(_vrfConsumer) != address(0)) {
            // Request randomness from VRF Consumer
            uint256 requestId = _vrfConsumer.requestRandomness(address(this), betId);

            // Store mappings
            _requestToBetId[requestId] = betId;
            _betToRequestId[betId] = requestId;

            emit RandomnessRequested(betId, requestId);
        } else {
            // Fallback to base implementation (emit event for manual resolution)
            super._requestRandomness(betId);
        }
    }
}
