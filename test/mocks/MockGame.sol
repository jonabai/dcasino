// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGameRegistry} from "../../src/interfaces/IGameRegistry.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";

/// @title MockGame - Mock game for testing
/// @notice Implements IGame interface for testing purposes
contract MockGame is IGame, IERC165 {
    bytes32 private _gameId;
    string private _gameName;
    address private _casino;
    address private _treasury;
    address private _gameRegistry;
    uint256 private _minBet;
    uint256 private _maxBet;
    bool private _isActive;
    bool private _isPaused;

    uint256 private _nextBetId;
    mapping(uint256 => BetLib.Bet) private _bets;
    mapping(address => uint256[]) private _playerBets;
    uint256[] private _pendingBets;

    constructor(
        string memory name,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress
    ) {
        _gameName = name;
        _casino = casinoAddress;
        _treasury = treasuryAddress;
        _gameRegistry = registryAddress;
        _minBet = 0.001 ether;
        _maxBet = 10 ether;
        _isActive = true;
        _isPaused = false;
        _nextBetId = 1;
    }

    // ============ ERC165 ============

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IGame).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ============ View Functions ============

    function gameId() external view override returns (bytes32) {
        return _gameId;
    }

    function gameName() external view override returns (string memory) {
        return _gameName;
    }

    function casino() external view override returns (address) {
        return _casino;
    }

    function treasury() external view override returns (address) {
        return _treasury;
    }

    function gameRegistry() external view override returns (address) {
        return _gameRegistry;
    }

    function getMinBet() external view override returns (uint256) {
        return _minBet;
    }

    function getMaxBet() external view override returns (uint256) {
        return _maxBet;
    }

    function isActive() external view override returns (bool) {
        return _isActive && !_isPaused;
    }

    function getHouseEdge() external pure override returns (uint256) {
        return 270; // 2.7%
    }

    function getBet(uint256 betId) external view override returns (BetLib.Bet memory) {
        return _bets[betId];
    }

    function getPlayerBets(address player) external view override returns (uint256[] memory) {
        return _playerBets[player];
    }

    function getPendingBets() external view override returns (uint256[] memory) {
        return _pendingBets;
    }

    function getPendingBetCount() external view override returns (uint256) {
        return _pendingBets.length;
    }

    // ============ Player Functions ============

    function placeBet(bytes calldata betData) external payable override returns (uint256 betId) {
        require(!_isPaused, "Game paused");
        require(msg.value >= _minBet, "Bet too small");
        require(msg.value <= _maxBet, "Bet too large");

        betId = _nextBetId++;

        _bets[betId] = BetLib.Bet({
            id: betId,
            player: msg.sender,
            amount: msg.value,
            potentialPayout: msg.value * 2, // Simple 2x payout for testing
            actualPayout: 0,
            timestamp: uint64(block.timestamp),
            status: BetLib.BetStatus.Pending,
            data: betData
        });

        _playerBets[msg.sender].push(betId);
        _pendingBets.push(betId);

        // Record bet in registry
        if (_gameRegistry != address(0)) {
            IGameRegistry(_gameRegistry).recordBet(address(this), msg.value);
        }

        emit BetPlaced(betId, msg.sender, msg.value, betData);
    }

    function cancelBet(uint256 betId) external override {
        BetLib.Bet storage bet = _bets[betId];
        require(bet.player == msg.sender, "Not bet owner");
        require(bet.status == BetLib.BetStatus.Pending, "Cannot cancel");

        bet.status = BetLib.BetStatus.Cancelled;
        bet.actualPayout = bet.amount;

        // Refund
        (bool success,) = msg.sender.call{value: bet.amount}("");
        require(success, "Refund failed");

        emit BetCancelled(betId, msg.sender);
    }

    // ============ Resolution Functions ============

    function resolveBet(uint256 betId, uint256[] calldata randomWords) external override {
        BetLib.Bet storage bet = _bets[betId];
        require(bet.status == BetLib.BetStatus.Pending, "Already resolved");

        // Simple resolution: if random % 2 == 0, win
        bool won = randomWords.length > 0 && randomWords[0] % 2 == 0;

        if (won) {
            bet.status = BetLib.BetStatus.Won;
            bet.actualPayout = bet.potentialPayout;
            (bool success,) = bet.player.call{value: bet.actualPayout}("");
            require(success, "Payout failed");
        } else {
            bet.status = BetLib.BetStatus.Lost;
            bet.actualPayout = 0;
        }

        // Remove from pending
        _removePendingBet(betId);

        emit BetResolved(betId, bet.player, bet.actualPayout, won);
    }

    function requestResolution(uint256 betId) external override {
        // In a real implementation, this would request VRF randomness
        emit RandomnessRequested(betId, block.timestamp);
    }

    // ============ Admin Functions ============

    function pause() external override {
        _isPaused = true;
    }

    function unpause() external override {
        _isPaused = false;
    }

    function setMinBet(uint256 newMinBet) external override {
        _minBet = newMinBet;
    }

    function setMaxBet(uint256 newMaxBet) external override {
        _maxBet = newMaxBet;
    }

    // ============ Mock-Only Functions ============

    function setGameId(bytes32 newGameId) external {
        _gameId = newGameId;
    }

    function setActive(bool active) external {
        _isActive = active;
    }

    // ============ Internal Functions ============

    function _removePendingBet(uint256 betId) internal {
        for (uint256 i = 0; i < _pendingBets.length; i++) {
            if (_pendingBets[i] == betId) {
                _pendingBets[i] = _pendingBets[_pendingBets.length - 1];
                _pendingBets.pop();
                break;
            }
        }
    }

    // ============ Receive ============

    receive() external payable {}
}
