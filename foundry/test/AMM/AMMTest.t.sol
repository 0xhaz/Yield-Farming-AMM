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
    WETH wftm;
    ERC20Mock TK1;
    ERC20Mock TK2;
    ERC20Mock USDC;
    ERC20Mock USD1;
    ERC20Mock USD2;
    BaseV1Pair pair;
    SpiritToken spirit;
    BaseV1Fees sLP1Fees;
    BaseV1Fees sLP2Fees;

    address vLP1Pair;
    address vLP2Pair;
    address sLP1Fees;
    address sLP2Fees;
    address user = address(0x123);
    address user2 = address(0x456);
    address admin = address(0x456);
    address protocol1 = address(0x789);
    address protocol2 = address(0xABC);

    function setUp() public {
        factory = new BaseV1Factory();
        wftm = new WETH();
        router = new BaseV1Router01(address(factory), address(wftm));
        TK1 = new ERC20Mock("Token 1", "TK1");
        TK2 = new ERC20Mock("Token 2", "TK2");
        USDC = new ERC20Mock("USD Coin", "USDC");
        USD1 = new ERC20Mock("USD Coin 1", "USD1");
        USD2 = new ERC20Mock("USD Coin 2", "USD2");
        spirit = new SpiritToken();
        sLP1Fees = new BaseV1Fees(address(wftm), address(TK1), address(factory));
        sLP2Fees = new BaseV1Fees(address(wftm), address(TK2), address(factory));

        wftm.deposit{value: 100e18}();

        TK1.mint(user, 100 ether);
        TK2.mint(user, 100 ether);
        USDC.mint(user, 100 ether);
        USD1.mint(user, 100 ether);
        USD2.mint(user, 100 ether);
        wftm.transfer(user, 100 ether);

        TK1.mint(user2, 100 ether);
        TK2.mint(user2, 100 ether);
        USDC.mint(user2, 100 ether);
        USD1.mint(user2, 100 ether);
        USD2.mint(user2, 100 ether);
        wftm.transfer(user2, 100 ether);

        factory.setSpiritMaker(address(spirit));

        wftm.approve(address(router), type(uint256).max);
        TK1.approve(address(router), type(uint256).max);
        TK2.approve(address(router), type(uint256).max);
        USDC.approve(address(router), type(uint256).max);
        USD1.approve(address(router), type(uint256).max);
        USD2.approve(address(router), type(uint256).max);

        router.addLiquidityFTM{value: 100e18}(address(TK1), false, 100e18, 100e18, 100e18, msg.sender, block.timestamp);

        vLP1Pair = factory.getPair(address(USDC), address(USD1), false);
        vLP2Pair = factory.getPair(address(USDC), address(USD2), false);

        // Initialize protocol address for vLP1
        factory.setProtocolAddress(vLP1Pair, protocol1);
        factory.setProtocolAddress(vLP2Pair, protocol2);

        // create sLP: USDC-USD2
        router.addLiquidity(
            address(USDC), address(USD2), true, 100e18, 100e18, 100e18, 100e18, msg.sender, block.timestamp
        );
    }
}
