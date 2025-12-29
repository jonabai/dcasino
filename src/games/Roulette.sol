// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseGameVRF} from "../abstracts/BaseGameVRF.sol";
import {IGame} from "../interfaces/IGame.sol";
import {BetLib} from "../libraries/BetLib.sol";
import {RouletteLib} from "../libraries/RouletteLib.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title Roulette - European Roulette Game
/// @notice Implements European roulette (single zero) with all standard bet types
/// @dev Extends BaseGameVRF for VRF-based randomness
contract Roulette is BaseGameVRF {
    using RouletteLib for RouletteLib.BetType;

    // ============ Constants ============

    /// @notice Maximum bets per spin (to limit gas usage)
    uint8 public constant MAX_BETS_PER_SPIN = 20;

    // ============ Storage ============

    /// @notice Mapping from bet ID to roulette-specific bet data
    mapping(uint256 => RouletteLib.RouletteBet[]) internal _rouletteBets;

    /// @notice Mapping from bet ID to winning number (after resolution)
    mapping(uint256 => uint8) internal _winningNumbers;

    /// @notice Storage gap for future upgrades
    uint256[38] private __gap_roulette;

    // ============ Events ============

    /// @notice Emitted when wheel spins
    event WheelSpun(uint256 indexed betId, uint8 winningNumber);

    /// @notice Emitted for each individual bet result
    event BetResult(
        uint256 indexed betId,
        uint8 betIndex,
        RouletteLib.BetType betType,
        uint256 amount,
        uint256 payout,
        bool won
    );

    // ============ Errors ============

    /// @notice Invalid bet type
    error InvalidBetType();

    /// @notice Invalid bet numbers
    error InvalidBetNumbers();

    /// @notice Too many bets
    error TooManyBets();

    /// @notice No bets provided
    error NoBets();

    // ============ Initializer ============

    /// @notice Initialize the Roulette game
    /// @param admin Admin address
    /// @param casinoAddress Casino contract address
    /// @param treasuryAddress Treasury contract address
    /// @param registryAddress Game registry address
    /// @param vrfConsumerAddress VRF consumer address
    function initialize(
        address admin,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress,
        address vrfConsumerAddress
    ) external initializer {
        __BaseGameVRF_init(
            admin,
            "European Roulette",
            casinoAddress,
            treasuryAddress,
            registryAddress,
            vrfConsumerAddress
        );
    }

    // ============ View Functions ============

    /// @inheritdoc IGame
    function getHouseEdge() external pure override returns (uint256) {
        return RouletteLib.HOUSE_EDGE;
    }

    /// @notice Get roulette bets for a bet ID
    /// @param betId The bet ID
    /// @return Array of roulette bets
    function getRouletteBets(uint256 betId) external view returns (RouletteLib.RouletteBet[] memory) {
        return _rouletteBets[betId];
    }

    /// @notice Get winning number for a resolved bet
    /// @param betId The bet ID
    /// @return The winning number (0-36)
    function getWinningNumber(uint256 betId) external view returns (uint8) {
        return _winningNumbers[betId];
    }

    /// @notice Calculate potential payout for bet data
    /// @param betData Encoded bet data
    /// @return maxPayout Maximum potential payout
    function calculateBetPayout(bytes calldata betData) external pure returns (uint256 maxPayout) {
        RouletteLib.RouletteBet[] memory bets = _decodeBetData(betData);
        return _calculateMaxPayout(bets);
    }

    // ============ Convenience Functions for Placing Bets ============

    /// @notice Place a straight bet (single number)
    /// @param number The number to bet on (0-36)
    function placeStraightBet(uint8 number) external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](1);
        numbers[0] = number;
        return _placeSingleBet(RouletteLib.BetType.Straight, numbers, msg.value);
    }

    /// @notice Place a split bet (two adjacent numbers)
    /// @param number1 First number
    /// @param number2 Second number
    function placeSplitBet(uint8 number1, uint8 number2) external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = number1;
        numbers[1] = number2;
        return _placeSingleBet(RouletteLib.BetType.Split, numbers, msg.value);
    }

    /// @notice Place a red bet
    function placeRedBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        return _placeSingleBet(RouletteLib.BetType.Red, RouletteLib.getRedNumbers(), msg.value);
    }

    /// @notice Place a black bet
    function placeBlackBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        return _placeSingleBet(RouletteLib.BetType.Black, RouletteLib.getBlackNumbers(), msg.value);
    }

    /// @notice Place an odd bet
    function placeOddBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](18);
        uint8 idx = 0;
        for (uint8 i = 1; i <= 36; i++) {
            if (i % 2 == 1) {
                numbers[idx++] = i;
            }
        }
        return _placeSingleBet(RouletteLib.BetType.Odd, numbers, msg.value);
    }

    /// @notice Place an even bet
    function placeEvenBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](18);
        uint8 idx = 0;
        for (uint8 i = 1; i <= 36; i++) {
            if (i % 2 == 0) {
                numbers[idx++] = i;
            }
        }
        return _placeSingleBet(RouletteLib.BetType.Even, numbers, msg.value);
    }

    /// @notice Place a low bet (1-18)
    function placeLowBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](18);
        for (uint8 i = 0; i < 18; i++) {
            numbers[i] = i + 1;
        }
        return _placeSingleBet(RouletteLib.BetType.Low, numbers, msg.value);
    }

    /// @notice Place a high bet (19-36)
    function placeHighBet() external payable nonReentrant whenNotPaused returns (uint256 betId) {
        uint8[] memory numbers = new uint8[](18);
        for (uint8 i = 0; i < 18; i++) {
            numbers[i] = i + 19;
        }
        return _placeSingleBet(RouletteLib.BetType.High, numbers, msg.value);
    }

    /// @notice Place a column bet
    /// @param column Column number (1, 2, or 3)
    function placeColumnBet(uint8 column) external payable nonReentrant whenNotPaused returns (uint256 betId) {
        return _placeSingleBet(RouletteLib.BetType.Column, RouletteLib.getColumnNumbers(column), msg.value);
    }

    /// @notice Place a dozen bet
    /// @param dozen Dozen number (1, 2, or 3)
    function placeDozenBet(uint8 dozen) external payable nonReentrant whenNotPaused returns (uint256 betId) {
        return _placeSingleBet(RouletteLib.BetType.Dozen, RouletteLib.getDozenNumbers(dozen), msg.value);
    }

    // ============ Internal Functions ============

    /// @notice Place a single bet (helper)
    function _placeSingleBet(
        RouletteLib.BetType betType,
        uint8[] memory numbers,
        uint256 amount
    ) internal returns (uint256 betId) {
        RouletteLib.RouletteBet[] memory bets = new RouletteLib.RouletteBet[](1);
        bets[0] = RouletteLib.RouletteBet({
            betType: betType,
            numbers: numbers,
            amount: amount
        });

        bytes memory betData = _encodeBetData(bets);
        return _placeBetInternal(msg.sender, betData, bets);
    }

    /// @notice Calculate potential payout for bets
    function _calculatePotentialPayout(uint256 /* amount */, bytes calldata betData)
        internal
        pure
        override
        returns (uint256)
    {
        RouletteLib.RouletteBet[] memory bets = _decodeBetData(betData);
        return _calculateMaxPayout(bets);
    }

    /// @notice Calculate maximum payout across all bets
    function _calculateMaxPayout(RouletteLib.RouletteBet[] memory bets) internal pure returns (uint256 maxPayout) {
        for (uint8 i = 0; i < bets.length; i++) {
            maxPayout += RouletteLib.calculatePayout(bets[i].betType, bets[i].amount);
        }
    }

    /// @notice Resolve a roulette bet with VRF randomness
    function _resolveBet(BetLib.Bet storage bet, uint256[] calldata randomWords)
        internal
        override
        returns (bool won, uint256 payout)
    {
        require(randomWords.length > 0, "No random words");

        // Get winning number (0-36)
        uint8 winningNumber = uint8(randomWords[0] % RouletteLib.TOTAL_NUMBERS);
        _winningNumbers[bet.id] = winningNumber;

        emit WheelSpun(bet.id, winningNumber);

        // Decode bets and calculate payouts
        RouletteLib.RouletteBet[] memory rouletteBets = _decodeBetData(bet.data);

        uint256 totalPayout = 0;
        bool anyWin = false;

        for (uint8 i = 0; i < rouletteBets.length; i++) {
            RouletteLib.RouletteBet memory rb = rouletteBets[i];
            bool betWon = RouletteLib.isWinner(rb.betType, rb.numbers, winningNumber);

            uint256 betPayout = 0;
            if (betWon) {
                betPayout = RouletteLib.calculatePayout(rb.betType, rb.amount);
                totalPayout += betPayout;
                anyWin = true;
            }

            emit BetResult(bet.id, i, rb.betType, rb.amount, betPayout, betWon);
        }

        return (anyWin, totalPayout);
    }

    /// @notice Encode bet data for storage
    function _encodeBetData(RouletteLib.RouletteBet[] memory bets) internal pure returns (bytes memory) {
        if (bets.length == 0) revert NoBets();
        if (bets.length > MAX_BETS_PER_SPIN) revert TooManyBets();

        // Validate all bets
        uint256 totalAmount = 0;
        for (uint8 i = 0; i < bets.length; i++) {
            if (!RouletteLib.validateBet(bets[i].betType, bets[i].numbers)) {
                revert InvalidBetNumbers();
            }
            totalAmount += bets[i].amount;
        }

        return abi.encode(bets);
    }

    /// @notice Decode bet data from storage
    function _decodeBetData(bytes memory data) internal pure returns (RouletteLib.RouletteBet[] memory) {
        return abi.decode(data, (RouletteLib.RouletteBet[]));
    }

    /// @notice Override placeBet to validate roulette-specific data
    function placeBet(bytes calldata betData)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (uint256 betId)
    {
        // Decode and validate bets
        RouletteLib.RouletteBet[] memory bets = _decodeBetData(betData);
        return _placeBetInternal(msg.sender, betData, bets);
    }

    /// @notice Internal bet placement logic
    function _placeBetInternal(
        address player,
        bytes memory betData,
        RouletteLib.RouletteBet[] memory bets
    ) internal returns (uint256 betId) {
        if (bets.length == 0) revert NoBets();
        if (bets.length > MAX_BETS_PER_SPIN) revert TooManyBets();

        // Validate bet amounts match msg.value
        uint256 totalBetAmount = 0;
        for (uint8 i = 0; i < bets.length; i++) {
            if (!RouletteLib.validateBet(bets[i].betType, bets[i].numbers)) {
                revert InvalidBetNumbers();
            }
            totalBetAmount += bets[i].amount;
        }

        if (totalBetAmount != msg.value) revert Errors.InvalidAmount();

        // Validate total bet amount
        BetLib.validateBetAmount(msg.value, _minBet, _maxBet);

        // Calculate potential payout
        uint256 potentialPayout = _calculateMaxPayout(bets);

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
        _bets[betId] = BetLib.createBet(betId, player, msg.value, potentialPayout, betData);

        // Store roulette bets
        for (uint8 i = 0; i < bets.length; i++) {
            _rouletteBets[betId].push(bets[i]);
        }

        // Track bet
        _playerBetIds[player].push(betId);
        _pendingBetIndex[betId] = _pendingBetIds.length;
        _pendingBetIds.push(betId);

        // Record statistics
        _gameRegistry.recordBet(address(this), msg.value);

        // Request randomness for bet resolution
        _requestRandomness(betId);

        emit BetPlaced(betId, player, msg.value, betData);
    }
}
