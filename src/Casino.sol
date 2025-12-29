// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICasino} from "./interfaces/ICasino.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title Casino - Main Registry and Admin Hub
/// @notice Central contract for managing the casino ecosystem
/// @dev UUPS upgradeable contract with role-based access control
contract Casino is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ICasino {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Role for pausing/unpausing the casino
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Current version of the contract
    string private constant VERSION = "1.0.0";

    // ============ Storage ============

    /// @notice Address of the treasury contract
    address private _treasury;

    /// @notice Address of the game registry contract
    address private _gameRegistry;

    /// @notice Storage gap for future upgrades
    uint256[48] private __gap;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initializes the casino contract
    /// @param admin Address to grant admin role
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ============ View Functions ============

    /// @inheritdoc ICasino
    function treasury() external view returns (address) {
        return _treasury;
    }

    /// @inheritdoc ICasino
    function gameRegistry() external view returns (address) {
        return _gameRegistry;
    }

    /// @inheritdoc ICasino
    function isPaused() external view returns (bool) {
        return paused();
    }

    /// @inheritdoc ICasino
    function version() external pure returns (string memory) {
        return VERSION;
    }

    // ============ Admin Functions ============

    /// @inheritdoc ICasino
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit CasinoPaused(msg.sender);
    }

    /// @inheritdoc ICasino
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit CasinoUnpaused(msg.sender);
    }

    /// @inheritdoc ICasino
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert Errors.InvalidAddress();

        address oldTreasury = _treasury;
        _treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /// @inheritdoc ICasino
    function setGameRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry == address(0)) revert Errors.InvalidAddress();

        address oldRegistry = _gameRegistry;
        _gameRegistry = newRegistry;

        emit GameRegistryUpdated(oldRegistry, newRegistry);
    }

    /// @inheritdoc ICasino
    function emergencyWithdrawETH(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert Errors.InvalidAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        if (address(this).balance < amount) revert Errors.InsufficientBalance();

        (bool success,) = to.call{value: amount}("");
        if (!success) revert Errors.TransferFailed();

        emit EmergencyWithdrawal(address(0), to, amount);
    }

    /// @inheritdoc ICasino
    function emergencyWithdrawToken(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert Errors.InvalidAddress();
        if (to == address(0)) revert Errors.InvalidAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdrawal(token, to, amount);
    }

    // ============ Internal Functions ============

    /// @notice Authorizes an upgrade
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ============ Receive Function ============

    /// @notice Allows the contract to receive ETH
    receive() external payable {}
}
