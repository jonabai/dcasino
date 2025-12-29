// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGame} from "../interfaces/IGame.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IGameRegistry} from "../interfaces/IGameRegistry.sol";
import {BetLib} from "../libraries/BetLib.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title BaseGame - Abstract Base Contract for Casino Games
/// @notice Provides common functionality for all casino games
/// @dev Games should inherit from this and implement game-specific logic
abstract contract BaseGame is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    IGame
{
    // ============ Constants ============

    /// @notice Role for game operators
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role for resolving bets
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ============ Storage ============

    /// @notice Unique identifier for this game
    bytes32 internal _gameId;

    /// @notice Human-readable game name
    string internal _gameName;

    /// @notice Casino contract address
    address internal _casino;

    /// @notice Treasury contract reference
    ITreasury internal _treasury;

    /// @notice Game registry contract reference
    IGameRegistry internal _gameRegistry;

    /// @notice Minimum bet amount
    uint256 internal _minBet;

    /// @notice Maximum bet amount
    uint256 internal _maxBet;

    /// @notice Counter for bet IDs
    uint256 internal _nextBetId;

    /// @notice Mapping of bet ID to bet info
    mapping(uint256 => BetLib.Bet) internal _bets;

    /// @notice Mapping of player address to their bet IDs
    mapping(address => uint256[]) internal _playerBetIds;

    /// @notice Array of pending bet IDs
    uint256[] internal _pendingBetIds;

    /// @notice Mapping to track pending bet indices for efficient removal
    mapping(uint256 => uint256) internal _pendingBetIndex;

    /// @notice Storage gap for future upgrades
    uint256[40] private __gap;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initializes the base game contract
    /// @param admin Address to grant admin role
    /// @param name Human-readable game name
    /// @param casinoAddress Address of the casino contract
    /// @param treasuryAddress Address of the treasury contract
    /// @param registryAddress Address of the game registry contract
    function __BaseGame_init(
        address admin,
        string memory name,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress
    ) internal onlyInitializing {
        if (admin == address(0)) revert Errors.InvalidAddress();
        if (casinoAddress == address(0)) revert Errors.InvalidAddress();
        if (treasuryAddress == address(0)) revert Errors.InvalidAddress();
        if (registryAddress == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, admin);
        _grantRole(RESOLVER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        _gameName = name;
        _casino = casinoAddress;
        _treasury = ITreasury(treasuryAddress);
        _gameRegistry = IGameRegistry(registryAddress);
        _nextBetId = 1;

        // Use treasury's bet limits as defaults
        _minBet = _treasury.minBet();
        _maxBet = _treasury.maxBet();
    }

    // ============ ERC165 ============

    /// @notice Returns true if this contract implements the interface defined by interfaceId
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IGame).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============ View Functions ============

    /// @inheritdoc IGame
    function gameId() external view returns (bytes32) {
        return _gameId;
    }

    /// @inheritdoc IGame
    function gameName() external view returns (string memory) {
        return _gameName;
    }

    /// @inheritdoc IGame
    function casino() external view returns (address) {
        return _casino;
    }

    /// @inheritdoc IGame
    function treasury() external view returns (address) {
        return address(_treasury);
    }

    /// @inheritdoc IGame
    function gameRegistry() external view returns (address) {
        return address(_gameRegistry);
    }

    /// @inheritdoc IGame
    function getMinBet() external view returns (uint256) {
        return _minBet;
    }

    /// @inheritdoc IGame
    function getMaxBet() external view returns (uint256) {
        return _maxBet;
    }

    /// @inheritdoc IGame
    function isActive() external view returns (bool) {
        return !paused() && _gameRegistry.isActiveGame(address(this));
    }

    /// @inheritdoc IGame
    function getBet(uint256 betId) external view returns (BetLib.Bet memory) {
        return _bets[betId];
    }

    /// @inheritdoc IGame
    function getPlayerBets(address player) external view returns (uint256[] memory) {
        return _playerBetIds[player];
    }

    /// @inheritdoc IGame
    function getPendingBets() external view returns (uint256[] memory) {
        return _pendingBetIds;
    }

    /// @inheritdoc IGame
    function getPendingBetCount() external view returns (uint256) {
        return _pendingBetIds.length;
    }

    // ============ Player Functions ============

    /// @inheritdoc IGame
    function placeBet(bytes calldata betData) external payable virtual nonReentrant whenNotPaused returns (uint256 betId) {
        // Validate bet amount
        BetLib.validateBetAmount(msg.value, _minBet, _maxBet);

        // Calculate potential payout (to be implemented by child)
        uint256 potentialPayout = _calculatePotentialPayout(msg.value, betData);

        // Check if treasury can cover the payout
        if (!_treasury.canPayout(potentialPayout)) {
            revert Errors.InsufficientTreasuryBalance();
        }

        // Transfer bet to treasury
        _treasury.receiveBet{value: msg.value}();

        // Reserve funds in treasury
        _treasury.reserveFunds(potentialPayout);

        // Create bet
        betId = _nextBetId++;
        _bets[betId] = BetLib.createBet(betId, msg.sender, msg.value, potentialPayout, betData);

        // Track bet
        _playerBetIds[msg.sender].push(betId);
        _pendingBetIndex[betId] = _pendingBetIds.length;
        _pendingBetIds.push(betId);

        // Record statistics
        _gameRegistry.recordBet(address(this), msg.value);

        // Request randomness for bet resolution
        _requestRandomness(betId);

        emit BetPlaced(betId, msg.sender, msg.value, betData);
    }

    /// @inheritdoc IGame
    function cancelBet(uint256 betId) external virtual nonReentrant {
        BetLib.Bet storage bet = _bets[betId];

        if (bet.id == 0) revert Errors.BetNotFound(betId);
        if (bet.player != msg.sender) revert Errors.Unauthorized();
        if (!BetLib.canCancel(bet)) revert Errors.BetCannotBeCancelled(betId);

        // Mark as cancelled
        BetLib.markAsCancelled(bet);

        // Release reserved funds
        _treasury.releaseFunds(bet.potentialPayout);

        // Process refund
        _treasury.processPayout(bet.player, bet.amount);

        // Remove from pending
        _removePendingBet(betId);

        emit BetCancelled(betId, msg.sender);
    }

    // ============ Resolution Functions ============

    /// @inheritdoc IGame
    function resolveBet(uint256 betId, uint256[] calldata randomWords) external virtual onlyRole(RESOLVER_ROLE) {
        BetLib.Bet storage bet = _bets[betId];

        if (bet.id == 0) revert Errors.BetNotFound(betId);
        if (BetLib.isResolved(bet)) revert Errors.BetAlreadyResolved(betId);

        // Resolve the bet (implemented by child)
        (bool won, uint256 payout) = _resolveBet(bet, randomWords);

        if (won) {
            BetLib.markAsWon(bet, payout);
            _treasury.processPayout(bet.player, payout);
        } else {
            BetLib.markAsLost(bet);
            // Release reserved funds back to treasury
            _treasury.releaseFunds(bet.potentialPayout);
        }

        // Collect protocol fee from the bet amount
        uint256 fee = (bet.amount * _treasury.feePercentage()) / 10_000;
        if (fee > 0) {
            _treasury.collectFee(fee);
        }

        // Remove from pending
        _removePendingBet(betId);

        emit BetResolved(betId, bet.player, payout, won);
    }

    /// @inheritdoc IGame
    function requestResolution(uint256 betId) external virtual {
        BetLib.Bet storage bet = _bets[betId];

        if (bet.id == 0) revert Errors.BetNotFound(betId);
        if (BetLib.isResolved(bet)) revert Errors.BetAlreadyResolved(betId);

        _requestRandomness(betId);
    }

    // ============ Admin Functions ============

    /// @inheritdoc IGame
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    /// @inheritdoc IGame
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    /// @inheritdoc IGame
    function setMinBet(uint256 newMinBet) external onlyRole(OPERATOR_ROLE) {
        if (newMinBet == 0) revert Errors.InvalidAmount();
        if (newMinBet > _maxBet) revert Errors.MinBetExceedsMaxBet();
        _minBet = newMinBet;
    }

    /// @inheritdoc IGame
    function setMaxBet(uint256 newMaxBet) external onlyRole(OPERATOR_ROLE) {
        if (newMaxBet == 0) revert Errors.InvalidAmount();
        if (newMaxBet < _minBet) revert Errors.MinBetExceedsMaxBet();
        _maxBet = newMaxBet;
    }

    /// @notice Sets the game ID (called by registry after registration)
    /// @param newGameId The game ID assigned by the registry
    function setGameId(bytes32 newGameId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _gameId = newGameId;
    }

    // ============ Internal Functions ============

    /// @notice Calculates the potential payout for a bet
    /// @dev Must be implemented by child contracts
    /// @param amount The bet amount
    /// @param betData Game-specific bet parameters
    /// @return The potential payout amount
    function _calculatePotentialPayout(uint256 amount, bytes calldata betData)
        internal
        view
        virtual
        returns (uint256);

    /// @notice Resolves a bet with random words
    /// @dev Must be implemented by child contracts
    /// @param bet The bet to resolve
    /// @param randomWords Random values from VRF
    /// @return won Whether the bet was won
    /// @return payout The payout amount
    function _resolveBet(BetLib.Bet storage bet, uint256[] calldata randomWords)
        internal
        virtual
        returns (bool won, uint256 payout);

    /// @notice Requests randomness for bet resolution
    /// @dev Override to integrate with VRF
    /// @param betId The bet ID
    function _requestRandomness(uint256 betId) internal virtual {
        // Default implementation just emits event
        // Override to integrate with Chainlink VRF
        emit RandomnessRequested(betId, block.timestamp);
    }

    /// @notice Removes a bet from the pending list
    /// @param betId The bet ID to remove
    function _removePendingBet(uint256 betId) internal {
        uint256 index = _pendingBetIndex[betId];
        uint256 lastIndex = _pendingBetIds.length - 1;

        if (index != lastIndex) {
            uint256 lastBetId = _pendingBetIds[lastIndex];
            _pendingBetIds[index] = lastBetId;
            _pendingBetIndex[lastBetId] = index;
        }

        _pendingBetIds.pop();
        delete _pendingBetIndex[betId];
    }

    /// @notice Authorizes an upgrade
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
