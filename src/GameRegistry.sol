// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IGameRegistry} from "./interfaces/IGameRegistry.sol";
import {IGame} from "./interfaces/IGame.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title GameRegistry - Game Registration and Management
/// @notice Manages game registration, enabling/disabling, and statistics tracking
/// @dev UUPS upgradeable contract with role-based access control
contract GameRegistry is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IGameRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ Constants ============

    /// @notice Role for managing games (register/deregister)
    bytes32 public constant GAME_MANAGER_ROLE = keccak256("GAME_MANAGER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ============ Storage ============

    /// @notice Set of all registered game addresses
    EnumerableSet.AddressSet private _registeredGames;

    /// @notice Mapping from game address to game info
    mapping(address => GameInfo) private _gameInfo;

    /// @notice Mapping from game ID to game address
    mapping(bytes32 => address) private _gameIdToAddress;

    /// @notice Address of the treasury contract
    ITreasury public treasury;

    /// @notice Storage gap for future upgrades
    uint256[45] private __gap;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initializes the game registry contract
    /// @param admin Address to grant admin role
    /// @param treasuryAddress Address of the treasury contract
    function initialize(address admin, address treasuryAddress) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();
        if (treasuryAddress == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GAME_MANAGER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        treasury = ITreasury(treasuryAddress);
    }

    // ============ View Functions ============

    /// @inheritdoc IGameRegistry
    function isRegisteredGame(address game) external view returns (bool) {
        return _registeredGames.contains(game);
    }

    /// @inheritdoc IGameRegistry
    function isActiveGame(address game) external view returns (bool) {
        if (!_registeredGames.contains(game)) return false;
        return _gameInfo[game].isActive;
    }

    /// @inheritdoc IGameRegistry
    function getGame(bytes32 gameId) external view returns (GameInfo memory info) {
        address gameAddress = _gameIdToAddress[gameId];
        if (gameAddress == address(0)) revert Errors.GameNotRegistered();
        return _gameInfo[gameAddress];
    }

    /// @inheritdoc IGameRegistry
    function getGameByAddress(address game) external view returns (GameInfo memory info) {
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();
        return _gameInfo[game];
    }

    /// @inheritdoc IGameRegistry
    function getAllGames() external view returns (address[] memory) {
        return _registeredGames.values();
    }

    /// @inheritdoc IGameRegistry
    function getActiveGames() external view returns (address[] memory) {
        uint256 totalGames = _registeredGames.length();
        uint256 activeCount = 0;

        // First pass: count active games
        for (uint256 i = 0; i < totalGames; i++) {
            if (_gameInfo[_registeredGames.at(i)].isActive) {
                activeCount++;
            }
        }

        // Second pass: populate array
        address[] memory activeGames = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < totalGames; i++) {
            address game = _registeredGames.at(i);
            if (_gameInfo[game].isActive) {
                activeGames[index] = game;
                index++;
            }
        }

        return activeGames;
    }

    /// @inheritdoc IGameRegistry
    function gameCount() external view returns (uint256) {
        return _registeredGames.length();
    }

    /// @inheritdoc IGameRegistry
    function getGameId(address game) external view returns (bytes32 gameId) {
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();
        return _gameInfo[game].gameId;
    }

    // ============ Game Management Functions ============

    /// @inheritdoc IGameRegistry
    function registerGame(address game, string calldata name) external onlyRole(GAME_MANAGER_ROLE) returns (bytes32 gameId) {
        if (game == address(0)) revert Errors.InvalidGameAddress();
        if (_registeredGames.contains(game)) revert Errors.GameAlreadyRegistered();

        // Verify game implements IGame interface
        if (!_supportsIGame(game)) revert Errors.GameDoesNotImplementInterface();

        // Generate unique game ID
        gameId = keccak256(abi.encodePacked(game, block.timestamp, name));

        // Store game info
        _gameInfo[game] = GameInfo({
            gameAddress: game,
            gameId: gameId,
            name: name,
            isActive: true,
            registeredAt: block.timestamp,
            totalBetsPlaced: 0,
            totalVolume: 0
        });

        _registeredGames.add(game);
        _gameIdToAddress[gameId] = game;

        emit GameRegistered(game, gameId, name);
    }

    /// @inheritdoc IGameRegistry
    function deregisterGame(address game) external onlyRole(GAME_MANAGER_ROLE) {
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();

        bytes32 gameId = _gameInfo[game].gameId;

        // Remove from storage
        delete _gameIdToAddress[gameId];
        delete _gameInfo[game];
        _registeredGames.remove(game);

        emit GameDeregistered(game, gameId);
    }

    /// @inheritdoc IGameRegistry
    function enableGame(address game) external onlyRole(GAME_MANAGER_ROLE) {
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();
        if (_gameInfo[game].isActive) return; // Already active

        _gameInfo[game].isActive = true;

        emit GameEnabled(game);
    }

    /// @inheritdoc IGameRegistry
    function disableGame(address game) external onlyRole(GAME_MANAGER_ROLE) {
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();
        if (!_gameInfo[game].isActive) return; // Already disabled

        _gameInfo[game].isActive = false;

        emit GameDisabled(game);
    }

    // ============ Statistics Functions ============

    /// @inheritdoc IGameRegistry
    function recordBet(address game, uint256 amount) external {
        // Only registered games can record bets
        if (!_registeredGames.contains(game)) revert Errors.GameNotRegistered();
        // Only the game itself can record its bets
        if (msg.sender != game) revert Errors.Unauthorized();

        _gameInfo[game].totalBetsPlaced++;
        _gameInfo[game].totalVolume += amount;

        emit BetRecorded(game, amount);
    }

    // ============ Admin Functions ============

    /// @notice Updates the treasury contract address
    /// @param newTreasury New treasury address
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert Errors.InvalidAddress();
        treasury = ITreasury(newTreasury);
    }

    // ============ Internal Functions ============

    /// @notice Checks if a contract implements the IGame interface
    /// @param game Address to check
    /// @return True if the contract implements IGame
    function _supportsIGame(address game) internal view returns (bool) {
        try IERC165(game).supportsInterface(type(IGame).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    /// @notice Authorizes an upgrade
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
