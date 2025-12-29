// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Errors} from "./Errors.sol";

/// @title PayoutLib - Payout calculation utilities
/// @notice Provides functions for calculating payouts and fees
/// @dev All percentages are in basis points (100 = 1%, 10000 = 100%)
library PayoutLib {
    // ============ Constants ============

    /// @notice Basis points denominator (100% = 10000)
    uint256 internal constant BASIS_POINTS = 10_000;

    /// @notice Maximum allowed fee percentage (50% = 5000 basis points)
    uint256 internal constant MAX_FEE_PERCENTAGE = 5_000;

    /// @notice Maximum allowed house edge (10% = 1000 basis points)
    uint256 internal constant MAX_HOUSE_EDGE = 1_000;

    // ============ Fee Calculation Functions ============

    /// @notice Calculates the fee amount from a given amount
    /// @param amount The amount to calculate fee from
    /// @param feePercentage Fee percentage in basis points
    /// @return fee The calculated fee amount
    function calculateFee(uint256 amount, uint256 feePercentage) internal pure returns (uint256 fee) {
        if (feePercentage > MAX_FEE_PERCENTAGE) {
            revert Errors.FeeTooHigh();
        }
        return (amount * feePercentage) / BASIS_POINTS;
    }

    /// @notice Calculates the net amount after fee deduction
    /// @param amount The gross amount
    /// @param feePercentage Fee percentage in basis points
    /// @return netAmount The amount after fee deduction
    /// @return fee The fee amount
    function calculateNetAmount(uint256 amount, uint256 feePercentage)
        internal
        pure
        returns (uint256 netAmount, uint256 fee)
    {
        fee = calculateFee(amount, feePercentage);
        netAmount = amount - fee;
    }

    // ============ Payout Calculation Functions ============

    /// @notice Calculates payout for a given multiplier
    /// @param betAmount The original bet amount
    /// @param multiplier The payout multiplier (e.g., 35 for 35:1)
    /// @return payout The total payout including original bet
    function calculatePayout(uint256 betAmount, uint256 multiplier) internal pure returns (uint256 payout) {
        // Payout = bet + (bet * multiplier)
        // For a 35:1 payout, if bet is 1 ETH, payout is 36 ETH (1 + 35)
        return betAmount + (betAmount * multiplier);
    }

    /// @notice Calculates payout for fractional odds
    /// @param betAmount The original bet amount
    /// @param numerator Numerator of the odds (e.g., 3 for 3:2)
    /// @param denominator Denominator of the odds (e.g., 2 for 3:2)
    /// @return payout The total payout including original bet
    function calculateFractionalPayout(uint256 betAmount, uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256 payout)
    {
        if (denominator == 0) {
            revert Errors.InvalidAmount();
        }
        // Payout = bet + (bet * numerator / denominator)
        // For 3:2 odds, if bet is 2 ETH, payout is 5 ETH (2 + 3)
        return betAmount + (betAmount * numerator) / denominator;
    }

    /// @notice Calculates even money payout (1:1)
    /// @param betAmount The original bet amount
    /// @return payout The total payout (2x the bet)
    function calculateEvenMoneyPayout(uint256 betAmount) internal pure returns (uint256 payout) {
        return betAmount * 2;
    }

    // ============ Roulette-Specific Payouts ============

    /// @notice Payout multipliers for roulette bet types
    /// @dev Multipliers represent the "to 1" portion (35:1 means 35)
    struct RoulettePayouts {
        uint256 straight; // Single number: 35:1
        uint256 split; // 2 numbers: 17:1
        uint256 street; // 3 numbers: 11:1
        uint256 corner; // 4 numbers: 8:1
        uint256 sixLine; // 6 numbers: 5:1
        uint256 dozen; // 12 numbers: 2:1
        uint256 column; // 12 numbers: 2:1
        uint256 evenMoney; // 18 numbers: 1:1

    }

    /// @notice Returns standard European roulette payout multipliers
    /// @return payouts The roulette payout configuration
    function getRoulettePayouts() internal pure returns (RoulettePayouts memory payouts) {
        return RoulettePayouts({
            straight: 35,
            split: 17,
            street: 11,
            corner: 8,
            sixLine: 5,
            dozen: 2,
            column: 2,
            evenMoney: 1
        });
    }

    /// @notice Calculates roulette payout based on bet type
    /// @param betAmount The bet amount
    /// @param numbersSelected How many numbers are covered by the bet
    /// @return payout The potential payout
    function calculateRoulettePayout(uint256 betAmount, uint256 numbersSelected)
        internal
        pure
        returns (uint256 payout)
    {
        if (numbersSelected == 0 || numbersSelected > 18) {
            revert Errors.InvalidBetParameters();
        }

        // European roulette formula: (36 / numbersSelected) - 1
        // This gives us the multiplier, then we add the original bet
        uint256 multiplier = (36 / numbersSelected) - 1;
        return betAmount + (betAmount * multiplier);
    }

    // ============ Blackjack-Specific Payouts ============

    /// @notice Calculates blackjack payout
    /// @param betAmount The bet amount
    /// @return payout The payout for a regular win (1:1)
    function calculateBlackjackWin(uint256 betAmount) internal pure returns (uint256 payout) {
        return calculateEvenMoneyPayout(betAmount);
    }

    /// @notice Calculates blackjack (natural 21) payout at 3:2
    /// @param betAmount The bet amount
    /// @return payout The payout for a blackjack (3:2)
    function calculateBlackjackPayout(uint256 betAmount) internal pure returns (uint256 payout) {
        return calculateFractionalPayout(betAmount, 3, 2);
    }

    /// @notice Calculates insurance payout at 2:1
    /// @param betAmount The insurance bet amount
    /// @return payout The payout if insurance wins
    function calculateInsurancePayout(uint256 betAmount) internal pure returns (uint256 payout) {
        return calculatePayout(betAmount, 2);
    }

    // ============ Treasury-Related Calculations ============

    /// @notice Calculates maximum payout based on available funds and ratio
    /// @param availableFunds Total available funds in treasury
    /// @param maxPayoutRatio Maximum payout ratio in basis points
    /// @return maxPayout The maximum allowed payout
    function calculateMaxPayout(uint256 availableFunds, uint256 maxPayoutRatio)
        internal
        pure
        returns (uint256 maxPayout)
    {
        return (availableFunds * maxPayoutRatio) / BASIS_POINTS;
    }

    /// @notice Checks if a payout is within treasury limits
    /// @param payout The requested payout amount
    /// @param availableFunds Total available funds in treasury
    /// @param maxPayoutRatio Maximum payout ratio in basis points
    /// @return isValid True if payout is within limits
    function isPayoutWithinLimits(uint256 payout, uint256 availableFunds, uint256 maxPayoutRatio)
        internal
        pure
        returns (bool isValid)
    {
        return payout <= calculateMaxPayout(availableFunds, maxPayoutRatio);
    }

    // ============ House Edge Calculations ============

    /// @notice Calculates house edge amount
    /// @param totalWagered Total amount wagered
    /// @param houseEdgeBps House edge in basis points (270 = 2.7% for European roulette)
    /// @return edge The house edge amount
    function calculateHouseEdge(uint256 totalWagered, uint256 houseEdgeBps) internal pure returns (uint256 edge) {
        if (houseEdgeBps > MAX_HOUSE_EDGE) {
            revert Errors.InvalidPercentage();
        }
        return (totalWagered * houseEdgeBps) / BASIS_POINTS;
    }
}
