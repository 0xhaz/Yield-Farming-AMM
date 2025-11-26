// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {BaseV1Router01} from "src/AMM/BaseV1Router01.sol";
import {WETH} from "src/tokens/WETH.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";
import {BaseV1Factory} from "src/factories/BaseV1Factory.sol";

contract BaseV1Router01Test is Test {
    BaseV1Factory factory;
    BaseV1Router01 router;
    WETH wftm;
    ERC20Mock TK1;
    ERC20Mock TK2;

    address user1 = address(0x123);
    address user2 = address(0x456);

    function setUp() public {
        factory = new BaseV1Factory();
        wftm = new WETH();
        router = new BaseV1Router01(address(factory), address(wftm));
        TK1 = new ERC20Mock("Token 1", "TK1");
        TK2 = new ERC20Mock("Token 2", "TK2");

        vm.deal(user1, 100_000 ether);
        vm.deal(user2, 100_000 ether);
        TK1.mint(user1, 1_000_000 ether);
        TK2.mint(user1, 1_000_000 ether);
        TK1.mint(user2, 1_000_000 ether);
        TK2.mint(user2, 1_000_000 ether);

        vm.prank(user1);
        TK1.approve(address(router), type(uint256).max);
        vm.prank(user1);
        TK2.approve(address(router), type(uint256).max);

        vm.prank(user2);
        TK1.approve(address(router), type(uint256).max);
        vm.prank(user2);
        TK2.approve(address(router), type(uint256).max);
    }

    function test_AddRemoveLiquidity() public {}
}
