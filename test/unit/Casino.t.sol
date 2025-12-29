// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Casino} from "../../src/Casino.sol";
import {ICasino} from "../../src/interfaces/ICasino.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract CasinoTest is Test {
    Casino public casinoImpl;
    Casino public casino;
    ERC20Mock public mockToken;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public upgrader = makeAddr("upgrader");
    address public treasury = makeAddr("treasury");
    address public gameRegistry = makeAddr("gameRegistry");
    address public randomUser = makeAddr("randomUser");

    event CasinoPaused(address indexed by);
    event CasinoUnpaused(address indexed by);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event GameRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        // Deploy implementation
        casinoImpl = new Casino();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(Casino.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(casinoImpl), initData);
        casino = Casino(payable(address(proxy)));

        // Deploy mock token
        mockToken = new ERC20Mock("Mock Token", "MTK");

        // Setup roles
        vm.startPrank(admin);
        casino.grantRole(casino.PAUSER_ROLE(), pauser);
        casino.grantRole(casino.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(address(casino), 10 ether);
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertTrue(casino.hasRole(casino.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(casino.hasRole(casino.PAUSER_ROLE(), admin));
        assertTrue(casino.hasRole(casino.UPGRADER_ROLE(), admin));
        assertEq(casino.version(), "1.0.0");
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        Casino newImpl = new Casino();
        vm.expectRevert(Errors.InvalidAddress.selector);
        new ERC1967Proxy(address(newImpl), abi.encodeWithSelector(Casino.initialize.selector, address(0)));
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert();
        casino.initialize(admin);
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        vm.prank(pauser);
        vm.expectEmit(true, false, false, false);
        emit CasinoPaused(pauser);
        casino.pause();

        assertTrue(casino.isPaused());
    }

    function test_Unpause() public {
        vm.prank(pauser);
        casino.pause();

        vm.prank(pauser);
        vm.expectEmit(true, false, false, false);
        emit CasinoUnpaused(pauser);
        casino.unpause();

        assertFalse(casino.isPaused());
    }

    function test_RevertWhen_PauseWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        casino.pause();
    }

    function test_RevertWhen_UnpauseWithoutRole() public {
        vm.prank(pauser);
        casino.pause();

        vm.prank(randomUser);
        vm.expectRevert();
        casino.unpause();
    }

    // ============ Set Treasury Tests ============

    function test_SetTreasury() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(address(0), treasury);
        casino.setTreasury(treasury);

        assertEq(casino.treasury(), treasury);
    }

    function test_UpdateTreasury() public {
        vm.prank(admin);
        casino.setTreasury(treasury);

        address newTreasury = makeAddr("newTreasury");
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(treasury, newTreasury);
        casino.setTreasury(newTreasury);

        assertEq(casino.treasury(), newTreasury);
    }

    function test_RevertWhen_SetTreasuryZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        casino.setTreasury(address(0));
    }

    function test_RevertWhen_SetTreasuryWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        casino.setTreasury(treasury);
    }

    // ============ Set Game Registry Tests ============

    function test_SetGameRegistry() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit GameRegistryUpdated(address(0), gameRegistry);
        casino.setGameRegistry(gameRegistry);

        assertEq(casino.gameRegistry(), gameRegistry);
    }

    function test_UpdateGameRegistry() public {
        vm.prank(admin);
        casino.setGameRegistry(gameRegistry);

        address newRegistry = makeAddr("newRegistry");
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit GameRegistryUpdated(gameRegistry, newRegistry);
        casino.setGameRegistry(newRegistry);

        assertEq(casino.gameRegistry(), newRegistry);
    }

    function test_RevertWhen_SetGameRegistryZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        casino.setGameRegistry(address(0));
    }

    function test_RevertWhen_SetGameRegistryWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        casino.setGameRegistry(gameRegistry);
    }

    // ============ Emergency Withdraw ETH Tests ============

    function test_EmergencyWithdrawETH() public {
        address recipient = makeAddr("recipient");
        uint256 withdrawAmount = 5 ether;
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawal(address(0), recipient, withdrawAmount);
        casino.emergencyWithdrawETH(recipient, withdrawAmount);

        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount);
        assertEq(address(casino).balance, 5 ether);
    }

    function test_RevertWhen_EmergencyWithdrawETHToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        casino.emergencyWithdrawETH(address(0), 1 ether);
    }

    function test_RevertWhen_EmergencyWithdrawETHZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAmount.selector);
        casino.emergencyWithdrawETH(randomUser, 0);
    }

    function test_RevertWhen_EmergencyWithdrawETHInsufficientBalance() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InsufficientBalance.selector);
        casino.emergencyWithdrawETH(randomUser, 100 ether);
    }

    function test_RevertWhen_EmergencyWithdrawETHWithoutRole() public {
        vm.prank(randomUser);
        vm.expectRevert();
        casino.emergencyWithdrawETH(randomUser, 1 ether);
    }

    // ============ Emergency Withdraw Token Tests ============

    function test_EmergencyWithdrawToken() public {
        // Mint tokens to casino
        uint256 tokenAmount = 1000 ether;
        mockToken.mint(address(casino), tokenAmount);

        address recipient = makeAddr("recipient");
        uint256 withdrawAmount = 500 ether;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdrawal(address(mockToken), recipient, withdrawAmount);
        casino.emergencyWithdrawToken(address(mockToken), recipient, withdrawAmount);

        assertEq(mockToken.balanceOf(recipient), withdrawAmount);
        assertEq(mockToken.balanceOf(address(casino)), tokenAmount - withdrawAmount);
    }

    function test_RevertWhen_EmergencyWithdrawTokenZeroTokenAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        casino.emergencyWithdrawToken(address(0), randomUser, 100 ether);
    }

    function test_RevertWhen_EmergencyWithdrawTokenToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAddress.selector);
        casino.emergencyWithdrawToken(address(mockToken), address(0), 100 ether);
    }

    function test_RevertWhen_EmergencyWithdrawTokenZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidAmount.selector);
        casino.emergencyWithdrawToken(address(mockToken), randomUser, 0);
    }

    function test_RevertWhen_EmergencyWithdrawTokenWithoutRole() public {
        mockToken.mint(address(casino), 1000 ether);

        vm.prank(randomUser);
        vm.expectRevert();
        casino.emergencyWithdrawToken(address(mockToken), randomUser, 100 ether);
    }

    // ============ Receive ETH Test ============

    function test_ReceiveETH() public {
        uint256 balanceBefore = address(casino).balance;

        vm.prank(randomUser);
        vm.deal(randomUser, 1 ether);
        (bool success,) = address(casino).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(casino).balance, balanceBefore + 1 ether);
    }

    // ============ View Functions Tests ============

    function test_Version() public view {
        assertEq(casino.version(), "1.0.0");
    }

    function test_IsPausedInitiallyFalse() public view {
        assertFalse(casino.isPaused());
    }

    function test_TreasuryInitiallyZero() public view {
        assertEq(casino.treasury(), address(0));
    }

    function test_GameRegistryInitiallyZero() public view {
        assertEq(casino.gameRegistry(), address(0));
    }
}
