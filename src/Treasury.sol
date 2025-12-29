    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ITreasury} from "./interfaces/ITreasury.sol";
import {Errors} from "./libraries/Errors.sol";
import {PayoutLib} from "./libraries/PayoutLib.sol";

/// @title Treasury - Casino Bankroll Management
/// @notice Manages casino funds, payouts, and fee collection
/// @dev UUPS upgradeable contract with role-based access control
contract Treasury is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    ITreasury
{
    // ============ Constants ============

    /// @notice Role for treasury managers (deposit/withdraw)
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    /// @notice Role for registered games (reserve/release/payout)
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Basis points denominator
    uint256 private constant BASIS_POINTS = 10_000;

    /// @notice Maximum fee percentage (10%)
    uint256 private constant MAX_FEE = 1_000;

    /// @notice Maximum payout ratio (50%)
    uint256 private constant MAX_PAYOUT_RATIO = 5_000;

    // ============ Storage ============

    /// @notice Total balance held by the treasury
    uint256 private _totalBalance;

    /// @notice Amount reserved for pending bets
    uint256 private _reservedAmount;

    /// @notice Total fees collected
    uint256 private _collectedFees;

    /// @notice Maximum payout ratio in basis points (default 5% = 500)
    uint256 public maxPayoutRatio;

    /// @notice Minimum bet amount
    uint256 public minBet;

    /// @notice Maximum bet amount
    uint256 public maxBet;

    /// @notice Protocol fee percentage in basis points (default 0.5% = 50)
    uint256 public feePercentage;

    /// @notice Storage gap for future upgrades
    uint256[43] private __gap;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initializes the treasury contract
    /// @param admin Address to grant admin role
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        // Set default values
        maxPayoutRatio = 500; // 5%
        minBet = 0.001 ether;
        maxBet = 10 ether;
        feePercentage = 50; // 0.5%
    }

    // ============ View Functions ============

    /// @inheritdoc ITreasury
    function getBalance() external view returns (uint256) {
        return _totalBalance;
    }

    /// @inheritdoc ITreasury
    function getAvailableBalance() external view returns (uint256) {
        return _getAvailableBalance();
    }

    /// @inheritdoc ITreasury
    function getReservedAmount() external view returns (uint256) {
        return _reservedAmount;
    }

    /// @inheritdoc ITreasury
    function getCollectedFees() external view returns (uint256) {
        return _collectedFees;
    }

    /// @inheritdoc ITreasury
    function canPayout(uint256 amount) external view returns (bool) {
        return amount <= getMaxPayout();
    }

    /// @inheritdoc ITreasury
    function getMaxPayout() public view returns (uint256) {
        uint256 available = _getAvailableBalance();
        return PayoutLib.calculateMaxPayout(available, maxPayoutRatio);
    }

    // ============ Deposit/Withdraw Functions ============

    /// @inheritdoc ITreasury
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert Errors.InvalidAmount();

        _totalBalance += msg.value;

        emit Deposit(msg.sender, msg.value);
    }

    /// @inheritdoc ITreasury
    function withdraw(uint256 amount) external nonReentrant onlyRole(TREASURY_ROLE) {
        if (amount == 0) revert Errors.InvalidAmount();
        if (amount > _getAvailableBalance()) revert Errors.InsufficientAvailableFunds();

        _totalBalance -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert Errors.TransferFailed();

        emit Withdrawal(msg.sender, amount);
    }

    // ============ Game Functions ============

    /// @inheritdoc ITreasury
    function receiveBet() external payable whenNotPaused onlyRole(GAME_ROLE) {
        if (msg.value == 0) revert Errors.InvalidAmount();

        _totalBalance += msg.value;
    }

    /// @inheritdoc ITreasury
    function reserveFunds(uint256 amount) external whenNotPaused onlyRole(GAME_ROLE) returns (bool) {
        if (amount == 0) revert Errors.InvalidAmount();

        uint256 available = _getAvailableBalance();
        uint256 maxPayout = PayoutLib.calculateMaxPayout(available, maxPayoutRatio);

        if (amount > maxPayout) revert Errors.InsufficientTreasuryBalance();

        _reservedAmount += amount;

        emit FundsReserved(msg.sender, amount);
        return true;
    }

    /// @inheritdoc ITreasury
    function releaseFunds(uint256 amount) external onlyRole(GAME_ROLE) {
        if (amount == 0) revert Errors.InvalidAmount();
        if (amount > _reservedAmount) revert Errors.InsufficientReservedFunds();

        _reservedAmount -= amount;

        emit FundsReleased(msg.sender, amount);
    }

    /// @inheritdoc ITreasury
    function processPayout(address player, uint256 amount) external nonReentrant whenNotPaused onlyRole(GAME_ROLE) {
        if (player == address(0)) revert Errors.InvalidPlayerAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        if (amount > _totalBalance) revert Errors.InsufficientBalance();

        // Reduce reserved amount if applicable
        if (_reservedAmount >= amount) {
            _reservedAmount -= amount;
        } else {
            _reservedAmount = 0;
        }

        _totalBalance -= amount;

        (bool success,) = player.call{value: amount}("");
        if (!success) revert Errors.PayoutFailed(player, amount);

        emit PayoutProcessed(msg.sender, player, amount);
    }

    /// @inheritdoc ITreasury
    function collectFee(uint256 amount) external onlyRole(GAME_ROLE) {
        if (amount == 0) return;

        _collectedFees += amount;

        emit FeeCollected(msg.sender, amount);
    }

    // ============ Admin Functions ============

    /// @inheritdoc ITreasury
    function setMaxPayoutRatio(uint256 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRatio == 0 || newRatio > MAX_PAYOUT_RATIO) {
            revert Errors.InvalidMaxPayoutRatio();
        }

        uint256 oldRatio = maxPayoutRatio;
        maxPayoutRatio = newRatio;

        emit MaxPayoutRatioUpdated(oldRatio, newRatio);
    }

    /// @inheritdoc ITreasury
    function setBetLimits(uint256 newMinBet, uint256 newMaxBet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMinBet == 0) revert Errors.InvalidAmount();
        if (newMinBet > newMaxBet) revert Errors.MinBetExceedsMaxBet();

        minBet = newMinBet;
        maxBet = newMaxBet;

        emit BetLimitsUpdated(newMinBet, newMaxBet);
    }

    /// @inheritdoc ITreasury
    function setFeePercentage(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > MAX_FEE) revert Errors.FeeTooHigh();

        uint256 oldFee = feePercentage;
        feePercentage = newFee;

        emit FeePercentageUpdated(oldFee, newFee);
    }

    /// @inheritdoc ITreasury
    function withdrawFees(address to) external nonReentrant onlyRole(TREASURY_ROLE) {
        if (to == address(0)) revert Errors.InvalidAddress();

        uint256 fees = _collectedFees;
        if (fees == 0) revert Errors.InvalidAmount();

        _collectedFees = 0;
        _totalBalance -= fees;

        (bool success,) = to.call{value: fees}("");
        if (!success) revert Errors.TransferFailed();

        emit Withdrawal(to, fees);
    }

    /// @notice Pauses the treasury
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the treasury
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============ Internal Functions ============

    /// @notice Returns the available balance (total - reserved)
    function _getAvailableBalance() internal view returns (uint256) {
        if (_totalBalance <= _reservedAmount) return 0;
        return _totalBalance - _reservedAmount;
    }

    /// @notice Authorizes an upgrade
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // ============ Receive Function ============

    /// @notice Allows the contract to receive ETH directly
    receive() external payable {
        _totalBalance += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
}
