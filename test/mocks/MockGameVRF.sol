// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseGameVRF} from "../../src/abstracts/BaseGameVRF.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";

/// @title MockGameVRF - Mock game with VRF integration for testing
/// @notice Implements BaseGameVRF for testing VRF functionality
contract MockGameVRF is BaseGameVRF {
    /// @notice House edge in basis points (2.7%)
    uint256 public constant HOUSE_EDGE = 270;

    /// @notice Payout multiplier (2x for simple win/lose)
    uint256 public constant PAYOUT_MULTIPLIER = 2;

    /// @notice Initialize the mock game
    /// @param admin Admin address
    /// @param casinoAddress Casino address
    /// @param treasuryAddress Treasury address
    /// @param registryAddress Registry address
    /// @param vrfConsumerAddress VRF Consumer address
    function initialize(
        address admin,
        address casinoAddress,
        address treasuryAddress,
        address registryAddress,
        address vrfConsumerAddress
    ) external initializer {
        __BaseGameVRF_init(
            admin,
            "MockGameVRF",
            casinoAddress,
            treasuryAddress,
            registryAddress,
            vrfConsumerAddress
        );
    }

    /// @inheritdoc IGame
    function getHouseEdge() external pure override returns (uint256) {
        return HOUSE_EDGE;
    }

    /// @notice Calculate potential payout (2x bet amount for testing)
    function _calculatePotentialPayout(uint256 amount, bytes calldata /* betData */)
        internal
        pure
        override
        returns (uint256)
    {
        return amount * PAYOUT_MULTIPLIER;
    }

    /// @notice Resolve bet: win if random % 2 == 0
    function _resolveBet(BetLib.Bet storage bet, uint256[] calldata randomWords)
        internal
        override
        returns (bool won, uint256 payout)
    {
        require(randomWords.length > 0, "No random words");

        // Simple resolution: even = win, odd = lose
        won = randomWords[0] % 2 == 0;
        payout = won ? bet.potentialPayout : 0;
    }

    /// @notice Manual resolution for testing (bypasses VRF)
    /// @param betId The bet ID
    /// @param randomWords Random words for resolution
    function manualResolve(uint256 betId, uint256[] calldata randomWords) external {
        require(hasRole(RESOLVER_ROLE, msg.sender), "Not resolver");
        _resolveWithRandomWords(betId, randomWords);
    }

    /// @notice Internal resolution with random words
    function _resolveWithRandomWords(uint256 betId, uint256[] calldata randomWords) internal {
        BetLib.Bet storage bet = _bets[betId];
        require(bet.id != 0, "Bet not found");
        require(!BetLib.isResolved(bet), "Already resolved");

        (bool won, uint256 payout) = _resolveBet(bet, randomWords);

        if (won) {
            BetLib.markAsWon(bet, payout);
            _treasury.processPayout(bet.player, payout);
        } else {
            BetLib.markAsLost(bet);
            _treasury.releaseFunds(bet.potentialPayout);
        }

        // Collect fee
        uint256 fee = (bet.amount * _treasury.feePercentage()) / 10_000;
        if (fee > 0) {
            _treasury.collectFee(fee);
        }

        _removePendingBet(betId);
        emit BetResolved(betId, bet.player, payout, won);
    }
}
