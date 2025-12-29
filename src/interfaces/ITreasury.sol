// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITreasury - Interface for the Casino Treasury
/// @notice Defines the interface for managing casino bankroll, payouts, and fees
/// @dev Implemented by Treasury.sol
interface ITreasury {
    // ============ Events ============

    /// @notice Emitted when funds are deposited into the treasury
    /// @param depositor Address that deposited
    /// @param amount Amount deposited in wei
    event Deposit(address indexed depositor, uint256 amount);

    /// @notice Emitted when funds are withdrawn from the treasury
    /// @param to Address receiving the withdrawal
    /// @param amount Amount withdrawn in wei
    event Withdrawal(address indexed to, uint256 amount);

    /// @notice Emitted when a payout is processed
    /// @param game Address of the game contract
    /// @param player Address receiving the payout
    /// @param amount Payout amount in wei
    event PayoutProcessed(address indexed game, address indexed player, uint256 amount);

    /// @notice Emitted when funds are reserved for a pending bet
    /// @param game Address of the game contract
    /// @param amount Amount reserved in wei
    event FundsReserved(address indexed game, uint256 amount);

    /// @notice Emitted when reserved funds are released
    /// @param game Address of the game contract
    /// @param amount Amount released in wei
    event FundsReleased(address indexed game, uint256 amount);

    /// @notice Emitted when a fee is collected
    /// @param game Address of the game contract
    /// @param amount Fee amount in wei
    event FeeCollected(address indexed game, uint256 amount);

    /// @notice Emitted when the maximum payout ratio is updated
    /// @param oldRatio Previous ratio in basis points
    /// @param newRatio New ratio in basis points
    event MaxPayoutRatioUpdated(uint256 oldRatio, uint256 newRatio);

    /// @notice Emitted when bet limits are updated
    /// @param newMinBet New minimum bet in wei
    /// @param newMaxBet New maximum bet in wei
    event BetLimitsUpdated(uint256 newMinBet, uint256 newMaxBet);

    /// @notice Emitted when the fee percentage is updated
    /// @param oldFee Previous fee in basis points
    /// @param newFee New fee in basis points
    event FeePercentageUpdated(uint256 oldFee, uint256 newFee);

    // ============ View Functions ============

    /// @notice Returns the total balance held by the treasury
    /// @return Total balance in wei
    function getBalance() external view returns (uint256);

    /// @notice Returns the amount available for payouts
    /// @dev Available = Total Balance - Reserved Amount
    /// @return Available amount in wei
    function getAvailableBalance() external view returns (uint256);

    /// @notice Returns the amount currently reserved for pending bets
    /// @return Reserved amount in wei
    function getReservedAmount() external view returns (uint256);

    /// @notice Returns the total fees collected
    /// @return Total fees in wei
    function getCollectedFees() external view returns (uint256);

    /// @notice Returns the maximum payout ratio in basis points
    /// @return Ratio in basis points (500 = 5%)
    function maxPayoutRatio() external view returns (uint256);

    /// @notice Returns the minimum bet amount
    /// @return Minimum bet in wei
    function minBet() external view returns (uint256);

    /// @notice Returns the maximum bet amount
    /// @return Maximum bet in wei
    function maxBet() external view returns (uint256);

    /// @notice Returns the protocol fee percentage in basis points
    /// @return Fee percentage (50 = 0.5%)
    function feePercentage() external view returns (uint256);

    /// @notice Checks if a payout amount can be covered
    /// @param amount The payout amount to check
    /// @return True if the treasury can cover the payout
    function canPayout(uint256 amount) external view returns (bool);

    /// @notice Returns the maximum payout currently allowed
    /// @return Maximum payout in wei
    function getMaxPayout() external view returns (uint256);

    // ============ State-Changing Functions ============

    /// @notice Deposits funds into the treasury
    /// @dev Must be payable, emits Deposit event
    function deposit() external payable;

    /// @notice Withdraws funds from the treasury
    /// @param amount Amount to withdraw in wei
    function withdraw(uint256 amount) external;

    /// @notice Reserves funds for a potential payout
    /// @dev Called by games when a bet is placed
    /// @param amount Amount to reserve in wei
    /// @return True if reservation was successful
    function reserveFunds(uint256 amount) external returns (bool);

    /// @notice Releases previously reserved funds
    /// @dev Called by games when a bet is resolved as lost
    /// @param amount Amount to release in wei
    function releaseFunds(uint256 amount) external;

    /// @notice Processes a payout to a player
    /// @dev Called by games when a bet is resolved as won
    /// @param player Address to receive the payout
    /// @param amount Payout amount in wei
    function processPayout(address player, uint256 amount) external;

    /// @notice Collects a fee from a bet
    /// @dev Called by games to collect protocol fees
    /// @param amount Fee amount in wei
    function collectFee(uint256 amount) external;

    /// @notice Receives bet amount from a player
    /// @dev Called by games when a bet is placed
    function receiveBet() external payable;

    // ============ Admin Functions ============

    /// @notice Sets the maximum payout ratio
    /// @param newRatio New ratio in basis points
    function setMaxPayoutRatio(uint256 newRatio) external;

    /// @notice Sets the bet limits
    /// @param newMinBet New minimum bet in wei
    /// @param newMaxBet New maximum bet in wei
    function setBetLimits(uint256 newMinBet, uint256 newMaxBet) external;

    /// @notice Sets the protocol fee percentage
    /// @param newFee New fee in basis points
    function setFeePercentage(uint256 newFee) external;

    /// @notice Withdraws collected fees to a specified address
    /// @param to Address to receive the fees
    function withdrawFees(address to) external;
}
