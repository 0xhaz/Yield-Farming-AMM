// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";
import {BaseV1Factory} from "src/factories/BaseV1Factory.sol";
import {BaseV1Pair} from "src/AMM/BaseV1Pair.sol";

contract BaseV1PairTest is Test {
    BaseV1Factory factory;
    ERC20Mock token1;
    ERC20Mock token2;
    BaseV1Pair pair;

    address constant user1 = address(0x123);
    address constant user2 = address(0x456);

    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    function setUp() public {
        factory = new BaseV1Factory();
        token1 = new ERC20Mock("Token 1", "TK1");
        token2 = new ERC20Mock("Token 2", "TK2");
        address pairAddress = factory.createPair(address(token1), address(token2), false);
        pair = BaseV1Pair(pairAddress);
    }

    function test_initialized() public {
        (uint256 reserve0, uint256 reserve1, uint256 timestamp) = pair.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
        assertEq(timestamp, 0);
    }

    function test_sampleReturnsCorrectPrices() public {
        // Setup: mint tokens and add liquidity
        deal(address(token1), address(pair), 1_000_000 ether);
        deal(address(token2), address(pair), 2_000_000 ether);
        pair.mint(address(this)); // initialize reserves

        // move forward in time and perform actions to generate observations
        // Time →       t0        t1        2       t3      t4
        // Swap # →     6         7         8       9       10
        // Price ↓    1.996e21 1.990e21 1.985e21 1.979e21 1.973e21
        for (uint256 i = 0; i < 10; i++) {
            // simulate time passing between observations
            vm.warp(block.timestamp + 1800); // 30 minutes
            // simulate a swap to change reserves
            deal(address(token1), address(this), 1_000 ether);
            // transfer input tokens to pair
            token1.transfer(address(pair), 1_000 ether);
            // swapping token1 for token2
            pair.swap(0, 900 ether, address(this), "");
        }

        // call sample function
        // tokenIn: address(token1)
        // amountIn: 1_000 ether
        // points: 5 TWAP data points
        // window: 1 (each point is 30 minutes apart, so total window is 2.5 hours)
        uint256[] memory prices = pair.sample(address(token1), 1_000 ether, 5, 1);

        // assert prices are non-zero and increasing or decreasing as expected
        for (uint256 i = 0; i < prices.length; i++) {
            assertGt(prices[i], 0, "Price should be greater than zero");
        }

        // TWAP prices decrease when swapping token1 for token2
        // emit log_named_array(key: "TWAP Prices", val: [1996557160815936910571 [1.996e21], 1990792181326264704856 [1.99e21], 1985050089956051322189 [1.985e21], 1979330750669735688897 [1.979e21], 1973634028507661842745 [1.973e21]])
        emit log_named_array("TWAP Prices", prices);

        (uint256 reserve0Cumulative, uint256 reserve1Cumulative,) = pair.currentCumulativePrices();
        // 18080838000000000000000000000 [1.808e28]
        console.log("Reserve0 Cumulative:", reserve0Cumulative);
        // 35927100000000000000000000000 [3.592e28]
        console.log("Reserve1 Cumulative:", reserve1Cumulative);
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        // 1009980000000000000000000 [1.009e24]
        console.log("Current Reserves0:", reserve0);
        // 1991000000000000000000000 [1.991e24] from swaps
        console.log("Current Reserves1:", reserve1);

        // 1004435198044553080384423 [1.004e24])
        console.log("TWAP avg price0 = ", reserve0Cumulative / block.timestamp);
        // 1971326164874551971 [1.971e18]
        console.log("Spot price0 = ", reserve1 * 1e18 / reserve0);
    }

    function testMint() public {
        deal(address(token1), user1, 1_000_000 ether);
        deal(address(token2), user1, 1_000_000 ether);
        vm.startPrank(user1);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user1);

        assertGt(liquidity, 0, "Liquidity should be greater than zero");
        vm.stopPrank();
    }

    function testBurn() public {
        // First, mint some liquidity
        deal(address(token1), user2, 1_000_000 ether);
        deal(address(token2), user2, 1_000_000 ether);
        vm.startPrank(user2);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user2);
        assertGt(liquidity, 0, "Liquidity should be greater than zero");

        // Now, burn the liquidity
        pair.transfer(address(pair), liquidity); // transfer LP tokens to pair
        uint256 amount0;
        uint256 amount1;
        (amount0, amount1) = pair.burn(user2);

        assertGt(amount0, 0, "Amount0 should be greater than zero");
        assertGt(amount1, 0, "Amount1 should be greater than zero");
        vm.stopPrank();
    }

    function testSwap() public {
        // First, mint some liquidity
        deal(address(token1), user1, 1_000_000 ether);
        deal(address(token2), user1, 1_000_000 ether);
        vm.startPrank(user1);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user1);
        assertGt(liquidity, 0, "Liquidity should be greater than zero");
        vm.stopPrank();

        // Now, perform a swap
        deal(address(token1), user2, 10_000 ether);
        vm.startPrank(user2);

        token1.approve(address(pair), type(uint256).max);
        token1.transfer(address(pair), 10_000 ether);

        // get current reserves
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        // function getAmountOut(uint amountIn, address tokenIn)
        // tokenIn is token1
        // amountIn is 10_000 ether
        // expect amountOut to be less than input due to fees
        uint256 amountOut = pair.getAmountOut(10_000 ether, address(token1));

        pair.swap(0, amountOut, user2, ""); // swap token1 for token2

        uint256 user2Token2Balance = token2.balanceOf(user2);
        //9784697439115259421938 [9.784e21]
        assertGt(user2Token2Balance, 0, "User2 should have received some token2");
        vm.stopPrank();
    }

    function testSkimAndSync() public {
        // First, mint some liquidity
        deal(address(token1), user1, 1_000_000 ether);
        deal(address(token2), user1, 1_000_000 ether);
        vm.startPrank(user1);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user1);
        assertGt(liquidity, 0, "Liquidity should be greater than zero");

        // Transfer extra tokens to pair to simulate imbalance
        token1.transfer(address(pair), 10_000 ether);
        token2.transfer(address(pair), 20_000 ether);

        uint256 beforeSkimToken1 = token1.balanceOf(user1);
        uint256 beforeSkimToken2 = token2.balanceOf(user1);

        // Call skim to send excess tokens to user1
        pair.skim(user1);

        uint256 afterSkimToken1 = token1.balanceOf(user1);
        uint256 afterSkimToken2 = token2.balanceOf(user1);

        assertEq(afterSkimToken1 - beforeSkimToken1, 10_000 ether, "User1 should receive excess token1");
        assertEq(afterSkimToken2 - beforeSkimToken2, 20_000 ether, "User1 should receive excess token2");

        // Now call sync to update reserves
        pair.sync();

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(reserve0, 500_000 ether, "Reserve0 should be updated correctly");
        assertEq(reserve1, 500_000 ether, "Reserve1 should be updated correctly");

        vm.stopPrank();
    }

    function testGetReserves() public {
        // First, mint some liquidity
        deal(address(token1), user1, 1_000_000 ether);
        deal(address(token2), user1, 1_000_000 ether);
        vm.startPrank(user1);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user1);
        assertGt(liquidity, 0, "Liquidity should be greater than zero");

        (uint256 reserve0, uint256 reserve1, uint256 timestamp) = pair.getReserves();
        assertEq(reserve0, 500_000 ether, "Reserve0 should match deposited amount");
        assertEq(reserve1, 500_000 ether, "Reserve1 should match deposited amount");
        assertGt(timestamp, 0, "Timestamp should be greater than zero");

        vm.stopPrank();
    }

    function testCurrentCumulativePrices() public {
        // First, mint some liquidity
        deal(address(token1), user1, 1_000_000 ether);
        deal(address(token2), user1, 1_000_000 ether);
        vm.startPrank(user1);

        token1.approve(address(pair), type(uint256).max);
        token2.approve(address(pair), type(uint256).max);

        token1.transfer(address(pair), 500_000 ether);
        token2.transfer(address(pair), 500_000 ether);

        uint256 liquidity = pair.mint(user1);
        assertGt(liquidity, 0, "Liquidity should be greater than zero");

        // Move forward in time
        vm.warp(block.timestamp + 3600); // 1 hour

        (uint256 reserve0Cumulative, uint256 reserve1Cumulative,) = pair.currentCumulativePrices();

        assertGt(reserve0Cumulative, 0, "Reserve0 Cumulative should be greater than zero");
        assertGt(reserve1Cumulative, 0, "Reserve1 Cumulative should be greater than zero");

        vm.stopPrank();
    }
}
