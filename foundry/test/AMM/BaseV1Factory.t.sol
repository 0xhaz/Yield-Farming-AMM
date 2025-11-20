// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "src/mock/ERC20Mock.sol";
import {BaseV1Factory} from "src/factories/BaseV1Factory.sol";
import {BaseV1Pair} from "src/AMM/BaseV1Pair.sol";

contract BaseV1FactoryTest is Test {
    BaseV1Factory factory;
    ERC20Mock token1;
    ERC20Mock token2;

    address user1 = address(0x123);
    address user2 = address(0x456);

    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint256);

    function setUp() public {
        factory = new BaseV1Factory();
        token1 = new ERC20Mock("Token 1", "TK1");
        token2 = new ERC20Mock("Token 2", "TK2");
    }

    function test_initialized() public {
        assertFalse(factory.isPaused());
        assertEq(factory.s_owner(), address(this));
        assertEq(factory.stableFee(), 2000);
        assertEq(factory.variableFee(), 500);
    }

    function test_createPair() public {
        vm.expectEmit(true, true, true, true);
        emit PairCreated(
            address(token1) < address(token2) ? address(token1) : address(token2),
            address(token1) < address(token2) ? address(token2) : address(token1),
            false,
            address(0x50822017daA3198010fa4d7610dB8d5B16C5E792),
            1
        );
        address pair = factory.createPair(address(token1), address(token2), false);

        address fetchedPair = factory.s_getPair(address(token1), address(token2), false);
        assertEq(pair, fetchedPair);
        assertTrue(factory.isPair(pair));

        (address tokenA, address tokenB, bool stable) = factory.getInitializable();
        assertEq(tokenA, address(token1) < address(token2) ? address(token1) : address(token2));
        assertEq(tokenB, address(token1) < address(token2) ? address(token2) : address(token1));
        assertEq(stable, false);

        uint256 allPairsLength = factory.allPairsLength();
        assertEq(allPairsLength, 1);
    }

    function test_createPair_revertIfPairExists() public {
        factory.createPair(address(token1), address(token2), false);
        vm.expectRevert("BaseV1: PAIR_EXISTS");
        factory.createPair(address(token1), address(token2), false);
    }

    function test_createPair_revertIfIdenticalAddresses() public {
        vm.expectRevert("BaseV1: IDENTICAL_ADDRESSES");
        factory.createPair(address(token1), address(token1), false);
    }

    function test_createPair_revertIfZeroAddress() public {
        vm.expectRevert("BaseV1: ZERO_ADDRESS");
        factory.createPair(address(0), address(token1), false);
    }

    function test_createMultiplePairs() public {
        factory.createPair(address(token1), address(token2), false);
        factory.createPair(address(token1), address(token2), true);
        ERC20Mock token3 = new ERC20Mock("Token 3", "TK3");
        factory.createPair(address(token1), address(token3), false);

        uint256 allPairsLength = factory.allPairsLength();
        assertEq(allPairsLength, 3);
    }

    function test_setStableFee() public {
        factory.setStableFee(1500);
        assertEq(factory.stableFee(), 1500);
    }

    function test_setVariableFee() public {
        factory.setVariableFee(300);
        assertEq(factory.variableFee(), 300);
    }

    function test_setOwner_and_acceptOwner() public {
        factory.setOwner(user1);
        vm.prank(user1);
        factory.acceptOwner();
        assertEq(factory.s_owner(), user1);
    }

    function test_setAdmin() public {
        factory.setAdmin(user2);
        assertEq(factory.s_admin(), user2);
    }

    function test_setPause() public {
        factory.setAdmin(user2);
        vm.prank(user2);
        factory.setPause(true);
        assertTrue(factory.isPaused());
    }

    function test_setProtocolAddress() public {
        address protocolAddress = address(0x789);
        factory.setProtocolAddress(address(0x111), protocolAddress);
        assertEq(factory.s_protocolAddresses(address(0x111)), protocolAddress);
    }

    function test_setSpiritMaker() public {
        address spiritMaker = address(0x999);
        factory.setSpiritMaker(spiritMaker);
        assertEq(factory.s_spiritMaker(), spiritMaker);
    }

    function test_setProtocolAddress_revertIfNotOwnerOrAdmin() public {
        address protocolAddress = address(0x789);
        vm.prank(user1);
        vm.expectRevert();
        factory.setProtocolAddress(address(0x111), protocolAddress);
    }

    function test_setSpiritMaker_revertIfNotOwner() public {
        address spiritMaker = address(0x999);
        vm.prank(user1);
        vm.expectRevert();
        factory.setSpiritMaker(spiritMaker);
    }

    function test_setPause_revertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.setPause(true);
    }

    function test_pairCodeHash() public {
        bytes32 pairCodeHash = factory.pairCodeHash();
        assertEq(pairCodeHash, keccak256(type(BaseV1Pair).creationCode));
    }
}
