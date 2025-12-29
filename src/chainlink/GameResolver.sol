// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {AutomationCompatibleInterface} from "./interfaces/IAutomationCompatible.sol";
import {IGame} from "../interfaces/IGame.sol";
import {IGameRegistry} from "../interfaces/IGameRegistry.sol";
import {BetLib} from "../libraries/BetLib.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title GameResolver - Chainlink Automation for Bet Resolution
/// @notice Automates bet resolution requests using Chainlink Automation
/// @dev Implements AutomationCompatibleInterface for Chainlink Automation
contract GameResolver is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    AutomationCompatibleInterface
{
    // ============ Constants ============

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role for Chainlink Automation forwarder
    bytes32 public constant FORWARDER_ROLE = keccak256("FORWARDER_ROLE");

    /// @notice Maximum bets to check per upkeep call
    uint256 public constant MAX_BETS_PER_CHECK = 50;

    /// @notice Maximum bets to resolve per upkeep call
    uint256 public constant MAX_BETS_PER_RESOLVE = 10;

    // ============ Storage ============

    /// @notice Game Registry contract
    IGameRegistry public gameRegistry;

    /// @notice Minimum time before a bet is eligible for resolution request
    uint256 public minResolutionDelay;

    /// @notice Maximum time a bet can be pending before considered stale
    uint256 public maxPendingTime;

    /// @notice Games enabled for automation
    mapping(address => bool) public automationEnabled;

    /// @notice List of games with automation enabled
    address[] public automatedGames;

    /// @notice Index of game in automatedGames array
    mapping(address => uint256) private _gameIndex;

    /// @notice Total upkeeps performed
    uint256 public totalUpkeeps;

    /// @notice Total bets resolved via automation
    uint256 public totalBetsResolved;

    /// @notice Storage gap for future upgrades
    uint256[40] private __gap;

    // ============ Events ============

    /// @notice Emitted when automation is enabled for a game
    event AutomationEnabled(address indexed game);

    /// @notice Emitted when automation is disabled for a game
    event AutomationDisabled(address indexed game);

    /// @notice Emitted when upkeep is performed
    event UpkeepPerformed(address indexed game, uint256[] betIds, uint256 timestamp);

    /// @notice Emitted when resolution delay is updated
    event ResolutionDelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @notice Emitted when max pending time is updated
    event MaxPendingTimeUpdated(uint256 oldTime, uint256 newTime);

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initialize the game resolver
    /// @param admin Admin address
    /// @param registry Game registry address
    /// @param resolutionDelay Minimum resolution delay in seconds
    /// @param pendingTime Maximum pending time in seconds
    function initialize(
        address admin,
        address registry,
        uint256 resolutionDelay,
        uint256 pendingTime
    ) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();
        if (registry == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        gameRegistry = IGameRegistry(registry);
        minResolutionDelay = resolutionDelay;
        maxPendingTime = pendingTime;
    }

    // ============ Automation Interface ============

    /// @inheritdoc AutomationCompatibleInterface
    /// @notice Check if any bets need resolution
    /// @dev Called off-chain by Chainlink Automation nodes
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (paused()) {
            return (false, "");
        }

        // Check each automated game for pending bets
        for (uint256 i = 0; i < automatedGames.length; i++) {
            address game = automatedGames[i];

            if (!gameRegistry.isActiveGame(game)) {
                continue;
            }

            uint256[] memory pendingBets = IGame(game).getPendingBets();
            uint256[] memory eligibleBets = new uint256[](MAX_BETS_PER_RESOLVE);
            uint256 eligibleCount = 0;

            for (uint256 j = 0; j < pendingBets.length && j < MAX_BETS_PER_CHECK; j++) {
                uint256 betId = pendingBets[j];
                BetLib.Bet memory bet = IGame(game).getBet(betId);

                // Check if bet is eligible for resolution
                if (_isEligibleForResolution(bet)) {
                    eligibleBets[eligibleCount] = betId;
                    eligibleCount++;

                    if (eligibleCount >= MAX_BETS_PER_RESOLVE) {
                        break;
                    }
                }
            }

            if (eligibleCount > 0) {
                // Trim the array to actual size
                uint256[] memory betsToResolve = new uint256[](eligibleCount);
                for (uint256 k = 0; k < eligibleCount; k++) {
                    betsToResolve[k] = eligibleBets[k];
                }

                return (true, abi.encode(game, betsToResolve));
            }
        }

        return (false, "");
    }

    /// @inheritdoc AutomationCompatibleInterface
    /// @notice Perform upkeep - request resolution for pending bets
    /// @dev Called on-chain by Chainlink Automation when checkUpkeep returns true
    function performUpkeep(bytes calldata performData) external override whenNotPaused {
        // Verify caller has forwarder role (Chainlink Automation forwarder)
        // In production, this should be restricted to the Automation forwarder
        // For flexibility, we allow FORWARDER_ROLE or DEFAULT_ADMIN_ROLE
        if (!hasRole(FORWARDER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Errors.Unauthorized();
        }

        (address game, uint256[] memory betIds) = abi.decode(performData, (address, uint256[]));
        _performUpkeep(game, betIds);
    }

    /// @notice Internal upkeep logic
    /// @param game The game address
    /// @param betIds The bet IDs to resolve
    function _performUpkeep(address game, uint256[] memory betIds) internal {
        // Verify game is still automated and active
        if (!automationEnabled[game] || !gameRegistry.isActiveGame(game)) {
            return;
        }

        // Request resolution for each bet
        for (uint256 i = 0; i < betIds.length; i++) {
            try IGame(game).requestResolution(betIds[i]) {
                totalBetsResolved++;
            } catch {
                // Continue with next bet if one fails
            }
        }

        totalUpkeeps++;
        emit UpkeepPerformed(game, betIds, block.timestamp);
    }

    // ============ View Functions ============

    /// @notice Get all automated games
    /// @return Array of game addresses with automation enabled
    function getAutomatedGames() external view returns (address[] memory) {
        return automatedGames;
    }

    /// @notice Get automation stats
    /// @return upkeeps Total upkeeps performed
    /// @return resolved Total bets resolved
    /// @return games Number of automated games
    function getStats()
        external
        view
        returns (uint256 upkeeps, uint256 resolved, uint256 games)
    {
        return (totalUpkeeps, totalBetsResolved, automatedGames.length);
    }

    /// @notice Check if a bet is eligible for resolution
    /// @param game The game address
    /// @param betId The bet ID
    /// @return True if eligible
    function isEligibleForResolution(address game, uint256 betId) external view returns (bool) {
        BetLib.Bet memory bet = IGame(game).getBet(betId);
        return _isEligibleForResolution(bet);
    }

    // ============ Admin Functions ============

    /// @notice Enable automation for a game
    /// @param game The game address
    function enableAutomation(address game) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (game == address(0)) revert Errors.InvalidAddress();
        if (!gameRegistry.isRegisteredGame(game)) revert Errors.GameNotRegistered();
        if (automationEnabled[game]) return;

        automationEnabled[game] = true;
        _gameIndex[game] = automatedGames.length;
        automatedGames.push(game);

        emit AutomationEnabled(game);
    }

    /// @notice Disable automation for a game
    /// @param game The game address
    function disableAutomation(address game) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!automationEnabled[game]) return;

        automationEnabled[game] = false;

        // Remove from array using swap-and-pop
        uint256 index = _gameIndex[game];
        uint256 lastIndex = automatedGames.length - 1;

        if (index != lastIndex) {
            address lastGame = automatedGames[lastIndex];
            automatedGames[index] = lastGame;
            _gameIndex[lastGame] = index;
        }

        automatedGames.pop();
        delete _gameIndex[game];

        emit AutomationDisabled(game);
    }

    /// @notice Set the minimum resolution delay
    /// @param newDelay New delay in seconds
    function setResolutionDelay(uint256 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldDelay = minResolutionDelay;
        minResolutionDelay = newDelay;
        emit ResolutionDelayUpdated(oldDelay, newDelay);
    }

    /// @notice Set the maximum pending time
    /// @param newTime New time in seconds
    function setMaxPendingTime(uint256 newTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldTime = maxPendingTime;
        maxPendingTime = newTime;
        emit MaxPendingTimeUpdated(oldTime, newTime);
    }

    /// @notice Set the game registry address
    /// @param newRegistry New registry address
    function setGameRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRegistry == address(0)) revert Errors.InvalidAddress();
        gameRegistry = IGameRegistry(newRegistry);
    }

    /// @notice Grant forwarder role to Chainlink Automation forwarder
    /// @param forwarder The forwarder address
    function setForwarder(address forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(FORWARDER_ROLE, forwarder);
    }

    /// @notice Revoke forwarder role
    /// @param forwarder The forwarder address
    function removeForwarder(address forwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(FORWARDER_ROLE, forwarder);
    }

    /// @notice Pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Manual upkeep trigger for testing or emergency
    /// @param game The game address
    /// @param betIds The bet IDs to resolve
    function manualUpkeep(address game, uint256[] calldata betIds)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _performUpkeep(game, betIds);
    }

    // ============ Internal Functions ============

    /// @notice Check if a bet is eligible for resolution
    /// @param bet The bet to check
    /// @return True if eligible
    function _isEligibleForResolution(BetLib.Bet memory bet) internal view returns (bool) {
        // Must be pending
        if (bet.status != BetLib.BetStatus.Pending) {
            return false;
        }

        // Must have passed minimum delay
        if (block.timestamp < bet.timestamp + minResolutionDelay) {
            return false;
        }

        // Must not be stale (past max pending time)
        if (maxPendingTime > 0 && block.timestamp > bet.timestamp + maxPendingTime) {
            return false;
        }

        return true;
    }

    /// @notice Authorize upgrade
    /// @param newImplementation New implementation address
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
