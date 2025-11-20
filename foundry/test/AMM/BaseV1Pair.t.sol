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
        console.log("Reserve0 Cumulative:", reserve0Cumulative);
        console.log("Reserve1 Cumulative:", reserve1Cumulative);
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        console.log("Current Reserves:", reserve0, reserve1);
    }
}
