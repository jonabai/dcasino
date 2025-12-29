// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RouletteLib - Roulette Game Library
/// @notice Provides bet types, validation, and payout calculations for European Roulette
/// @dev European roulette has numbers 0-36 (single zero)
library RouletteLib {
    // ============ Constants ============

    /// @notice Total numbers on the wheel (0-36)
    uint8 public constant TOTAL_NUMBERS = 37;

    /// @notice Maximum number on the wheel
    uint8 public constant MAX_NUMBER = 36;

    /// @notice House edge in basis points (2.7% for European roulette)
    uint256 public constant HOUSE_EDGE = 270;

    // ============ Enums ============

    /// @notice Types of bets available in roulette
    enum BetType {
        Straight,   // Single number (35:1)
        Split,      // Two adjacent numbers (17:1)
        Street,     // Three numbers in a row (11:1)
        Corner,     // Four numbers in a square (8:1)
        Line,       // Six numbers (two rows) (5:1)
        Column,     // 12 numbers in a column (2:1)
        Dozen,      // 12 numbers (1-12, 13-24, 25-36) (2:1)
        Red,        // Red numbers (1:1)
        Black,      // Black numbers (1:1)
        Odd,        // Odd numbers (1:1)
        Even,       // Even numbers (1:1)
        Low,        // 1-18 (1:1)
        High        // 19-36 (1:1)
    }

    // ============ Structs ============

    /// @notice Represents a single roulette bet
    struct RouletteBet {
        BetType betType;
        uint8[] numbers;    // Numbers covered by the bet
        uint256 amount;     // Bet amount
    }

    // ============ Payout Multipliers ============

    /// @notice Get payout multiplier for a bet type (in addition to original bet)
    /// @param betType The type of bet
    /// @return multiplier The payout multiplier
    function getPayoutMultiplier(BetType betType) internal pure returns (uint256 multiplier) {
        if (betType == BetType.Straight) return 35;
        if (betType == BetType.Split) return 17;
        if (betType == BetType.Street) return 11;
        if (betType == BetType.Corner) return 8;
        if (betType == BetType.Line) return 5;
        if (betType == BetType.Column) return 2;
        if (betType == BetType.Dozen) return 2;
        // Even money bets (Red, Black, Odd, Even, Low, High)
        return 1;
    }

    /// @notice Calculate potential payout for a bet
    /// @param betType The type of bet
    /// @param amount The bet amount
    /// @return payout Total payout including original bet
    function calculatePayout(BetType betType, uint256 amount) internal pure returns (uint256 payout) {
        uint256 multiplier = getPayoutMultiplier(betType);
        return amount + (amount * multiplier);
    }

    // ============ Number Properties ============

    /// @notice Red numbers on a European roulette wheel
    function isRed(uint8 number) internal pure returns (bool) {
        if (number == 0) return false;
        // Red numbers: 1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36
        if (number == 1 || number == 3 || number == 5 || number == 7 || number == 9) return true;
        if (number == 12 || number == 14 || number == 16 || number == 18) return true;
        if (number == 19 || number == 21 || number == 23 || number == 25 || number == 27) return true;
        if (number == 30 || number == 32 || number == 34 || number == 36) return true;
        return false;
    }

    /// @notice Check if number is black
    function isBlack(uint8 number) internal pure returns (bool) {
        if (number == 0) return false;
        return !isRed(number);
    }

    /// @notice Check if number is odd
    function isOdd(uint8 number) internal pure returns (bool) {
        if (number == 0) return false;
        return number % 2 == 1;
    }

    /// @notice Check if number is even
    function isEven(uint8 number) internal pure returns (bool) {
        if (number == 0) return false;
        return number % 2 == 0;
    }

    /// @notice Check if number is low (1-18)
    function isLow(uint8 number) internal pure returns (bool) {
        return number >= 1 && number <= 18;
    }

    /// @notice Check if number is high (19-36)
    function isHigh(uint8 number) internal pure returns (bool) {
        return number >= 19 && number <= 36;
    }

    /// @notice Get the column (1, 2, or 3) for a number
    function getColumn(uint8 number) internal pure returns (uint8) {
        if (number == 0) return 0;
        uint8 mod = number % 3;
        if (mod == 1) return 1;  // First column: 1,4,7,10...34
        if (mod == 2) return 2;  // Second column: 2,5,8,11...35
        return 3;                 // Third column: 3,6,9,12...36
    }

    /// @notice Get the dozen (1, 2, or 3) for a number
    function getDozen(uint8 number) internal pure returns (uint8) {
        if (number == 0) return 0;
        if (number <= 12) return 1;
        if (number <= 24) return 2;
        return 3;
    }

    // ============ Bet Validation ============

    /// @notice Validate a straight bet (single number)
    function validateStraight(uint8[] memory numbers) internal pure returns (bool) {
        return numbers.length == 1 && numbers[0] <= MAX_NUMBER;
    }

    /// @notice Validate a split bet (two adjacent numbers)
    function validateSplit(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 2) return false;
        uint8 a = numbers[0];
        uint8 b = numbers[1];

        if (a > MAX_NUMBER || b > MAX_NUMBER) return false;

        // Ensure a < b for easier checking
        if (a > b) (a, b) = (b, a);

        // Check for horizontal adjacency (same row)
        // Valid if b = a + 1 and they're in the same row (a % 3 != 0)
        if (b == a + 1 && a % 3 != 0 && a != 0) return true;

        // Check for vertical adjacency (same column)
        // Valid if b = a + 3
        if (b == a + 3) return true;

        // Special case: 0 can split with 1, 2, or 3
        if (a == 0 && (b == 1 || b == 2 || b == 3)) return true;

        return false;
    }

    /// @notice Validate a street bet (three numbers in a row)
    function validateStreet(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 3) return false;

        // Sort numbers
        uint8 a = numbers[0];
        uint8 b = numbers[1];
        uint8 c = numbers[2];

        // Simple bubble sort
        if (a > b) (a, b) = (b, a);
        if (b > c) (b, c) = (c, b);
        if (a > b) (a, b) = (b, a);

        if (c > MAX_NUMBER) return false;

        // Street must be consecutive: a, a+1, a+2
        // And a must be the start of a row (a % 3 == 1)
        if (a == 0) return false;
        return (a % 3 == 1) && (b == a + 1) && (c == a + 2);
    }

    /// @notice Validate a corner bet (four numbers in a square)
    function validateCorner(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 4) return false;

        // Sort numbers
        uint8[4] memory sorted;
        for (uint8 i = 0; i < 4; i++) {
            sorted[i] = numbers[i];
        }
        // Simple sort
        for (uint8 i = 0; i < 3; i++) {
            for (uint8 j = i + 1; j < 4; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }

        uint8 a = sorted[0];
        uint8 b = sorted[1];
        uint8 c = sorted[2];
        uint8 d = sorted[3];

        if (d > MAX_NUMBER || a == 0) return false;

        // Corner: a, a+1, a+3, a+4 where a is not at right edge (a % 3 != 0)
        return (a % 3 != 0) && (b == a + 1) && (c == a + 3) && (d == a + 4);
    }

    /// @notice Validate a line bet (six numbers - two rows)
    function validateLine(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 6) return false;

        // Sort numbers
        uint8[6] memory sorted;
        for (uint8 i = 0; i < 6; i++) {
            sorted[i] = numbers[i];
        }
        for (uint8 i = 0; i < 5; i++) {
            for (uint8 j = i + 1; j < 6; j++) {
                if (sorted[i] > sorted[j]) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }

        uint8 a = sorted[0];
        if (a == 0 || sorted[5] > MAX_NUMBER) return false;

        // Line must start at beginning of row (a % 3 == 1)
        if (a % 3 != 1) return false;

        // Must be two consecutive rows: a,a+1,a+2,a+3,a+4,a+5
        for (uint8 i = 1; i < 6; i++) {
            if (sorted[i] != a + i) return false;
        }

        return true;
    }

    /// @notice Validate a column bet
    function validateColumn(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 12) return false;

        // Check first number to determine which column
        uint8 col = getColumn(numbers[0]);
        if (col == 0) return false;

        // Verify all 12 numbers belong to the same column
        for (uint8 i = 0; i < 12; i++) {
            if (numbers[i] > MAX_NUMBER || numbers[i] == 0) return false;
            if (getColumn(numbers[i]) != col) return false;
        }

        return true;
    }

    /// @notice Validate a dozen bet
    function validateDozen(uint8[] memory numbers) internal pure returns (bool) {
        if (numbers.length != 12) return false;

        // Check first number to determine which dozen
        uint8 dozen = getDozen(numbers[0]);
        if (dozen == 0) return false;

        // Verify all 12 numbers belong to the same dozen
        for (uint8 i = 0; i < 12; i++) {
            if (numbers[i] > MAX_NUMBER || numbers[i] == 0) return false;
            if (getDozen(numbers[i]) != dozen) return false;
        }

        return true;
    }

    /// @notice Validate an even-money bet (red, black, odd, even, low, high)
    function validateEvenMoney(uint8[] memory numbers, BetType betType) internal pure returns (bool) {
        if (numbers.length != 18) return false;

        for (uint8 i = 0; i < 18; i++) {
            uint8 n = numbers[i];
            if (n > MAX_NUMBER || n == 0) return false;

            if (betType == BetType.Red && !isRed(n)) return false;
            if (betType == BetType.Black && !isBlack(n)) return false;
            if (betType == BetType.Odd && !isOdd(n)) return false;
            if (betType == BetType.Even && !isEven(n)) return false;
            if (betType == BetType.Low && !isLow(n)) return false;
            if (betType == BetType.High && !isHigh(n)) return false;
        }

        return true;
    }

    /// @notice Validate a bet based on its type
    function validateBet(BetType betType, uint8[] memory numbers) internal pure returns (bool) {
        if (betType == BetType.Straight) return validateStraight(numbers);
        if (betType == BetType.Split) return validateSplit(numbers);
        if (betType == BetType.Street) return validateStreet(numbers);
        if (betType == BetType.Corner) return validateCorner(numbers);
        if (betType == BetType.Line) return validateLine(numbers);
        if (betType == BetType.Column) return validateColumn(numbers);
        if (betType == BetType.Dozen) return validateDozen(numbers);

        // Even money bets
        return validateEvenMoney(numbers, betType);
    }

    // ============ Win Detection ============

    /// @notice Check if a bet is a winner given the winning number
    /// @param betType The type of bet
    /// @param numbers The numbers covered by the bet
    /// @param winningNumber The number that came up
    /// @return True if the bet is a winner
    function isWinner(BetType betType, uint8[] memory numbers, uint8 winningNumber) internal pure returns (bool) {
        // For simple bet types, just check if winning number is in the array
        for (uint8 i = 0; i < numbers.length; i++) {
            if (numbers[i] == winningNumber) {
                return true;
            }
        }
        return false;
    }

    // ============ Encoding/Decoding ============

    /// @notice Encode a roulette bet for storage
    function encodeBet(BetType betType, uint8[] memory numbers) internal pure returns (bytes memory) {
        return abi.encode(uint8(betType), numbers);
    }

    /// @notice Decode a roulette bet from storage
    function decodeBet(bytes memory data) internal pure returns (BetType betType, uint8[] memory numbers) {
        uint8 betTypeInt;
        (betTypeInt, numbers) = abi.decode(data, (uint8, uint8[]));
        betType = BetType(betTypeInt);
    }

    // ============ Helper Functions ============

    /// @notice Get all red numbers
    function getRedNumbers() internal pure returns (uint8[] memory) {
        uint8[] memory reds = new uint8[](18);
        reds[0] = 1; reds[1] = 3; reds[2] = 5; reds[3] = 7; reds[4] = 9;
        reds[5] = 12; reds[6] = 14; reds[7] = 16; reds[8] = 18;
        reds[9] = 19; reds[10] = 21; reds[11] = 23; reds[12] = 25; reds[13] = 27;
        reds[14] = 30; reds[15] = 32; reds[16] = 34; reds[17] = 36;
        return reds;
    }

    /// @notice Get all black numbers
    function getBlackNumbers() internal pure returns (uint8[] memory) {
        uint8[] memory blacks = new uint8[](18);
        blacks[0] = 2; blacks[1] = 4; blacks[2] = 6; blacks[3] = 8;
        blacks[4] = 10; blacks[5] = 11; blacks[6] = 13; blacks[7] = 15; blacks[8] = 17;
        blacks[9] = 20; blacks[10] = 22; blacks[11] = 24; blacks[12] = 26; blacks[13] = 28; blacks[14] = 29;
        blacks[15] = 31; blacks[16] = 33; blacks[17] = 35;
        return blacks;
    }

    /// @notice Get numbers for a column (1, 2, or 3)
    function getColumnNumbers(uint8 column) internal pure returns (uint8[] memory) {
        require(column >= 1 && column <= 3, "Invalid column");
        uint8[] memory nums = new uint8[](12);
        uint8 start = column == 3 ? 3 : column;
        for (uint8 i = 0; i < 12; i++) {
            nums[i] = start + (i * 3);
        }
        return nums;
    }

    /// @notice Get numbers for a dozen (1, 2, or 3)
    function getDozenNumbers(uint8 dozen) internal pure returns (uint8[] memory) {
        require(dozen >= 1 && dozen <= 3, "Invalid dozen");
        uint8[] memory nums = new uint8[](12);
        uint8 start = ((dozen - 1) * 12) + 1;
        for (uint8 i = 0; i < 12; i++) {
            nums[i] = start + i;
        }
        return nums;
    }
}
