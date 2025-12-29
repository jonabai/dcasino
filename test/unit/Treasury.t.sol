// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Treasury} from "../../src/Treasury.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TreasuryTest is Test {
    Treasury public treasuryImpl;
    Treasury public treasury;

    address public admin = makeAddr("admin");
    address public treasuryManager = makeAddr("treasuryManager");
    address public game = makeAddr("game");
    address public player = makeAddr("player");
    address public randomUser = makeAddr("randomUser");

    uint256 public constant INITIAL_DEPOSIT = 100 ether;

    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event PayoutProcessed(address indexed game, address indexed player, uint256 amount);
    event FundsReserved(address indexed game, uint256 amount);
    event FundsReleased(address indexed game, uint256 amount);
    event FeeCollected(address indexed game, uint256 amount);
    event MaxPayoutRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event BetLimitsUpdated(uint256 newMinBet, uint256 newMaxBet);
    event FeePercentageUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        // Deploy implementation
        treasuryImpl = new Treasury();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(Treasury.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(treasuryImpl), initData);
        treasury = Treasury(payable(address(proxy)));

        // Setup roles
        vm.startPrank(admin);
        treasury.grantRole(treasury.TREASURY_ROLE(), treasuryManager);
        treasury.grantRole(treasury.GAME_ROLE(), game);
        vm.stopPrank();

        // Fund accounts
        vm.deal(admin, 1000 ether);
        vm.deal(treasuryManager, 1000 ether);
        vm.deal(game, 1000 ether);
        vm.deal(player, 100 ether);
        vm.deal(randomUser, 100 ether);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(treasury.maxPayoutRatio(), 500); // 5%
        assertEq(treasury.minBet(), 0.001 ether);
        assertEq(treasury.maxBet(), 10 ether);
        assertEq(treasury.feePercentage(), 50); // 0.5%
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(treasury.hasRole(treasury.TREASURY_ROLE(), admin));
        assertTrue(treasury.hasRole(treasury.UPGRADER_ROLE(), admin));
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        Treasury newImpl = new Treasury();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(address(newImpl), abi.encodeWithSelector(Treasury.initialize.selector, address(0)));
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert();
        treasury.initialize(admin);
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 10 ether;

        vm.prank(randomUser);
        vm.expectEmit(true, false, false, true);
        emit Deposit(randomUser, depositAmount);
        treasury.deposit{value: depositAmount}();

        assertEq(treasury.getBalance(), depositAmount);
    }

    function test_DepositViaReceive() public {
        uint256 depositAmount = 5 ether;

        vm.prank(randomUser);
        vm.expectEmit(true, false, false, true);
        emit Deposit(randomUser, depositAmount);
        (bool success,) = address(treasury).call{value: depositAmount}("");
        assertTrue(success);

        assertEq(treasury.getBalance(), depositAmount);
    }

    function test_RevertWhen_DepositZero() public {
        vm.prank(randomUser);
        vm.expectRevert(Errors.InvalidAmount.selector);
        treasury.deposit{value: 0}();
    }

    function test_RevertWhen_DepositWhenPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.prank(randomUser);
        vm.expectRevert();
        treasury.deposit{value: 1 ether}();
    }

    // ============ Withdraw Tests ============

    function test_Withdraw() public {
        // First deposit
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        uint256 withdrawAmount = 10 ether;
        uint256 balanceBefore = treasuryManager.balance;

        vm.prank(treasuryManager);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(treasuryManager, withdrawAmount);
        treasury.withdraw(withdrawAmount);

        assertEq(treasury.getBalance(), INITIAL_DEPOSIT - withdrawAmount);
        assertEq(treasuryManager.balance, balanceBefore + withdrawAmount);
    }

    function test_RevertWhen_WithdrawWithoutRole() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(randomUser);
        vm.expectRevert();
        treasury.withdraw(1 ether);
    }

    function test_RevertWhen_WithdrawZero() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(treasuryManager);
        vm.expectRevert(Errors.InvalidAmount.selector);
        treasury.withdraw(0);
    }

    function test_RevertWhen_WithdrawExceedsAvailable() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(treasuryManager);
        vm.expectRevert(Errors.InsufficientAvailableFunds.selector);
        treasury.withdraw(INITIAL_DEPOSIT + 1);
    }

    // ============ Reserve Funds Tests ============

    function test_ReserveFunds() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        uint256 reserveAmount = 1 ether;

        vm.prank(game);
        vm.expectEmit(true, false, false, true);
        emit FundsReserved(game, reserveAmount);
        bool success = treasury.reserveFunds(reserveAmount);

        assertTrue(success);
        assertEq(treasury.getReservedAmount(), reserveAmount);
    }

    function test_RevertWhen_ReserveFundsWithoutRole() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(randomUser);
        vm.expectRevert();
        treasury.reserveFunds(1 ether);
    }

    function test_RevertWhen_ReserveFundsExceedsMaxPayout() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        // Max payout is 5% of 100 ETH = 5 ETH
        vm.prank(game);
        vm.expectRevert(Errors.InsufficientTreasuryBalance.selector);
        treasury.reserveFunds(6 ether);
    }

    function test_ReserveFundsReducesAvailable() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        uint256 reserveAmount = 2 ether;
        uint256 availableBefore = treasury.getAvailableBalance();

        vm.prank(game);
        treasury.reserveFunds(reserveAmount);

        assertEq(treasury.getAvailableBalance(), availableBefore - reserveAmount);
    }

    // ============ Release Funds Tests ============

    function test_ReleaseFunds() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        uint256 reserveAmount = 2 ether;
        vm.prank(game);
        treasury.reserveFunds(reserveAmount);

        vm.prank(game);
        vm.expectEmit(true, false, false, true);
        emit FundsReleased(game, reserveAmount);
        treasury.releaseFunds(reserveAmount);

        assertEq(treasury.getReservedAmount(), 0);
    }

    function test_RevertWhen_ReleaseFundsExceedsReserved() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(game);
        treasury.reserveFunds(1 ether);

        vm.prank(game);
        vm.expectRevert(Errors.InsufficientReservedFunds.selector);
        treasury.releaseFunds(2 ether);
    }

    // ============ Process Payout Tests ============

    function test_ProcessPayout() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        // Reserve funds first
        uint256 payoutAmount = 2 ether;
        vm.prank(game);
        treasury.reserveFunds(payoutAmount);

        uint256 playerBalanceBefore = player.balance;

        vm.prank(game);
        vm.expectEmit(true, true, false, true);
        emit PayoutProcessed(game, player, payoutAmount);
        treasury.processPayout(player, payoutAmount);

        assertEq(player.balance, playerBalanceBefore + payoutAmount);
        assertEq(treasury.getBalance(), INITIAL_DEPOSIT - payoutAmount);
        assertEq(treasury.getReservedAmount(), 0);
    }

    function test_RevertWhen_ProcessPayoutToZeroAddress() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(game);
        vm.expectRevert(Errors.InvalidPlayerAddress.selector);
        treasury.processPayout(address(0), 1 ether);
    }

    function test_RevertWhen_ProcessPayoutExceedsBalance() public {
        vm.prank(randomUser);
        treasury.deposit{value: 1 ether}();

        vm.prank(game);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        treasury.processPayout(player, 2 ether);
    }

    // ============ Collect Fee Tests ============

    function test_CollectFee() public {
        uint256 feeAmount = 0.1 ether;

        vm.prank(game);
        vm.expectEmit(true, false, false, true);
        emit FeeCollected(game, feeAmount);
        treasury.collectFee(feeAmount);

        assertEq(treasury.getCollectedFees(), feeAmount);
    }

    function test_CollectFeeZeroDoesNothing() public {
        vm.prank(game);
        treasury.collectFee(0);

        assertEq(treasury.getCollectedFees(), 0);
    }

    // ============ Withdraw Fees Tests ============

    function test_WithdrawFees() public {
        // Deposit and collect fee
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        uint256 feeAmount = 1 ether;
        vm.prank(game);
        treasury.collectFee(feeAmount);

        address feeRecipient = makeAddr("feeRecipient");
        uint256 recipientBalanceBefore = feeRecipient.balance;

        vm.prank(treasuryManager);
        treasury.withdrawFees(feeRecipient);

        assertEq(feeRecipient.balance, recipientBalanceBefore + feeAmount);
        assertEq(treasury.getCollectedFees(), 0);
    }

    function test_RevertWhen_WithdrawFeesToZeroAddress() public {
        vm.prank(game);
        treasury.collectFee(1 ether);

        vm.prank(randomUser);
        treasury.deposit{value: 10 ether}();

        vm.prank(treasuryManager);
        vm.expectRevert(Errors.InvalidAddress.selector);
        treasury.withdrawFees(address(0));
    }

    function test_RevertWhen_WithdrawFeesNoFeesCollected() public {
        vm.prank(treasuryManager);
        vm.expectRevert(Errors.InvalidAmount.selector);
        treasury.withdrawFees(admin);
    }

    // ============ Receive Bet Tests ============

    function test_ReceiveBet() public {
        uint256 betAmount = 1 ether;

        vm.prank(game);
        treasury.receiveBet{value: betAmount}();

        assertEq(treasury.getBalance(), betAmount);
    }

    function test_RevertWhen_ReceiveBetWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        treasury.receiveBet{value: 1 ether}();
    }

    // ============ Admin Configuration Tests ============

    function test_SetMaxPayoutRatio() public {
        uint256 newRatio = 1000; // 10%

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit MaxPayoutRatioUpdated(500, newRatio);
        treasury.setMaxPayoutRatio(newRatio);

        assertEq(treasury.maxPayoutRatio(), newRatio);
    }

    function test_RevertWhen_SetMaxPayoutRatioZero() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidMaxPayoutRatio.selector);
        treasury.setMaxPayoutRatio(0);
    }

    function test_RevertWhen_SetMaxPayoutRatioTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidMaxPayoutRatio.selector);
        treasury.setMaxPayoutRatio(5001); // > 50%
    }

    function test_SetBetLimits() public {
        uint256 newMin = 0.01 ether;
        uint256 newMax = 100 ether;

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit BetLimitsUpdated(newMin, newMax);
        treasury.setBetLimits(newMin, newMax);

        assertEq(treasury.minBet(), newMin);
        assertEq(treasury.maxBet(), newMax);
    }

    function test_RevertWhen_SetBetLimitsMinZero() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAmount.selector);
        treasury.setBetLimits(0, 10 ether);
    }

    function test_RevertWhen_SetBetLimitsMinExceedsMax() public {
        vm.prank(admin);
        vm.expectRevert(Errors.MinBetExceedsMaxBet.selector);
        treasury.setBetLimits(10 ether, 1 ether);
    }

    function test_SetFeePercentage() public {
        uint256 newFee = 100; // 1%

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit FeePercentageUpdated(50, newFee);
        treasury.setFeePercentage(newFee);

        assertEq(treasury.feePercentage(), newFee);
    }

    function test_RevertWhen_SetFeePercentageTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(Errors.FeeTooHigh.selector);
        treasury.setFeePercentage(1001); // > 10%
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        vm.prank(admin);
        treasury.pause();

        vm.prank(randomUser);
        vm.expectRevert();
        treasury.deposit{value: 1 ether}();
    }

    function test_Unpause() public {
        vm.prank(admin);
        treasury.pause();

        vm.prank(admin);
        treasury.unpause();

        vm.prank(randomUser);
        treasury.deposit{value: 1 ether}();

        assertEq(treasury.getBalance(), 1 ether);
    }

    // ============ View Function Tests ============

    function test_CanPayout() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        // Max payout is 5% of 100 ETH = 5 ETH
        assertTrue(treasury.canPayout(5 ether));
        assertFalse(treasury.canPayout(6 ether));
    }

    function test_GetMaxPayout() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        // Max payout is 5% of 100 ETH = 5 ETH
        assertEq(treasury.getMaxPayout(), 5 ether);
    }

    function test_GetAvailableBalanceWithReserved() public {
        vm.prank(randomUser);
        treasury.deposit{value: INITIAL_DEPOSIT}();

        vm.prank(game);
        treasury.reserveFunds(2 ether);

        assertEq(treasury.getAvailableBalance(), INITIAL_DEPOSIT - 2 ether);
    }
}
