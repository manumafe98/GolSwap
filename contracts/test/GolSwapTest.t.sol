// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DeployGolSwap} from "../script/DeployGolSwap.s.sol";
import {GolSwap} from "../src/GolSwap.sol";
import {Gol} from "../src/Gol.sol";

contract GolSwapTest is Test {
    GolSwap public golSwap;
    Gol public golToken;

    address public USER = makeAddr("user");
    address public LIQUIDITY_ADDER = makeAddr("liquidityAdder");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    event Swap(address indexed user, uint256 inputAmount, uint256 outputAmount, bool ethToGol);
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 golAmount);
    event LiquidityRemoved(address indexed provider, uint256 amount);

    modifier initLiquidityPool() {
        approveTokenAmount(USER, 10 ether);
        vm.prank(USER);
        golSwap.init{value: 0.01 ether}(10 ether);
        _;
    }

    function setUp() external {
        DeployGolSwap deployer = new DeployGolSwap();
        (golSwap, golToken) = deployer.run();

        vm.deal(USER, STARTING_USER_BALANCE);
        golToken.mint(USER, 40 ether);
    }

    function testTotalLiquidityPreInitialization() public view {
        assertEq(golSwap.getTotalLiquidity(), 0);
    }

    function testRunInitWithInsufficientEth() public {
        approveTokenAmount(USER, 10 ether);

        vm.prank(USER);
        vm.expectRevert(GolSwap.GolSwap__InvalidRatio.selector);
        golSwap.init{value: 0.001 ether}(10 ether);
    }

        function testRunInitWithInsufficientGol() public {
        approveTokenAmount(USER, 9 ether);

        vm.prank(USER);
        vm.expectRevert(GolSwap.GolSwap__InvalidRatio.selector);
        golSwap.init{value: 0.01 ether}(9 ether);
    }

    function testRunInitialize() public initLiquidityPool {
        assertEq(golSwap.getTotalLiquidity(), 0.01 ether);
        assertEq(golSwap.getProvidedLiquidityByUser(USER), 0.01 ether);
    }

    function testRunInitAfterPoolWasAlreadyInitialized() public initLiquidityPool {
        vm.prank(USER);
        vm.expectRevert(GolSwap.GolSwap__PoolAlreadyInitialized.selector);
        golSwap.init{value: 0.01 ether}(10 ether);
    }

    function testEthToGol() public initLiquidityPool {
        uint256 previousEthBalance = USER.balance;
        uint256 previousGolBalance = golToken.balanceOf(USER);

        vm.prank(USER);
        golSwap.ethToGol{value: 0.009 ether}();

        uint256 currentEthBalance = USER.balance;
        uint256 currentGolBalance = golToken.balanceOf(USER);

        assertGt(previousEthBalance, currentEthBalance);
        assertGt(currentGolBalance, previousGolBalance);
    }

    function testEthToGolSwapEmitsEvent() public initLiquidityPool {
        vm.prank(USER);
        vm.expectEmit();
        emit Swap(USER, 0.009 ether, 4729352237389975227, true);
        golSwap.ethToGol{value: 0.009 ether}();
    }

    function testGolToEth() public initLiquidityPool {
        uint256 previousEthBalance = USER.balance;
        uint256 previousGolBalance = golToken.balanceOf(USER);

        approveTokenAmount(USER, 1 ether);
        vm.prank(USER);
        golSwap.golToEth(1 ether);

        uint256 currentEthBalance = USER.balance;
        uint256 currentGolBalance = golToken.balanceOf(USER);

        assertGt(currentEthBalance, previousEthBalance);
        assertGt(previousGolBalance, currentGolBalance);
    }

    function testAddLiquidity() public initLiquidityPool {
        uint256 previousTotalLiquidity = golSwap.getTotalLiquidity();

        approveTokenAmount(LIQUIDITY_ADDER, 10 ether);
        vm.deal(LIQUIDITY_ADDER, STARTING_USER_BALANCE);
        golToken.mint(LIQUIDITY_ADDER, 40 ether);

        vm.prank(LIQUIDITY_ADDER);
        golSwap.addLiquidity{value: 0.005 ether}(5 ether);

        uint256 currentTotalLiquidity = golSwap.getTotalLiquidity();
        uint256 userProvidedLiquidity = golSwap.getProvidedLiquidityByUser(USER);

        assertEq(0.01 ether, userProvidedLiquidity);
        assertGt(currentTotalLiquidity, previousTotalLiquidity);
    }

    function approveTokenAmount(address _user, uint256 _golTokenAmount) private {
        vm.prank(_user);
        golToken.approve(address(golSwap), _golTokenAmount);
    }
}