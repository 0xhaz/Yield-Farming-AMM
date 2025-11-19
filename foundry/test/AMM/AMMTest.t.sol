// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {BaseV1Fees} from "src/AMM/BaseV1Fees.sol";
import {BaseV1Pair} from "src/AMM/BaseV1Pair.sol";
import {BaseV1Router01} from "src/AMM/BaseV1Router01.sol";
import {WETH} from "src/tokens/WETH.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";
import {BaseV1Factory} from "src/factories/BaseV1Factory.sol";
import {BEP20} from "src/tokens/BEP20.sol";
import {SpiritToken} from "src/tokens/SpiritToken.sol";

contract AMMTest is Test {
    BaseV1Factory factory;
    BaseV1Router01 router;
    WETH weth;
    ERC20Mock TK1;
    ERC20Mock TK2;
    ERC20Mock USDC;
    ERC20Mock USD1;
    ERC20Mock USD2;
    BaseV1Pair pair;
    SpiritToken spirit;

    function setUp() public {
        factory = new BaseV1Factory();
        weth = new WETH();
        router = new BaseV1Router01(address(factory), address(weth));
        TK1 = new ERC20Mock("Token 1", "TK1");
        TK2 = new ERC20Mock("Token 2", "TK2");
        USDC = new ERC20Mock("USD Coin", "USDC");
        USD1 = new ERC20Mock("USD Coin 1", "USD1");
        USD2 = new ERC20Mock("USD Coin 2", "USD2");
        spirit = new SpiritToken();

        // Create a pair for TK1 and TK2
        // factory.createPair(address(TK1), address(TK2));
        // address pairAddress = factory.getPair(address(TK1), address(TK2));
        // pair = BaseV1Pair(pairAddress);
    }
}
