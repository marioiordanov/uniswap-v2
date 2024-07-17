// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {BaseTest} from "./BaseTest.t.sol";

contract UniswapV2FactoryTest is BaseTest {
    UniswapV2Factory private factory;
    address private tokenA = makeAddr("first token");
    address private tokenB = makeAddr("second token");

    modifier createPair() {
        factory.createPair(tokenA, tokenB);
        _;
    }

    function setUp() public {
        factory = new UniswapV2Factory();
    }

    function testFuzz_CreatePairIsSuccessful(
        address token0,
        address token1
    ) public {
        vm.assume(token0 != token1);
        vm.assume(token0 != address(0));
        vm.assume(token1 != address(0));

        factory.createPair(token0, token1);
    }

    function test_CreatePairWithTheSameTokensReverts() public {
        address token = address(1);
        vm.expectRevert(
            UniswapV2Factory.AddressesInPairCannotBeTheSame.selector
        );
        factory.createPair(token, token);
    }

    function test_CreatePairWithZeroAddressReverts() public {
        vm.expectRevert(UniswapV2Factory.ZeroAddressNotAllowed.selector);
        factory.createPair(address(1), address(0));
    }

    function test_GetPairWithSameArgumentsButDifferentPositions()
        public
        createPair
    {
        assertEq(
            factory.getPair(tokenA, tokenB),
            factory.getPair(tokenB, tokenA)
        );
    }

    function test_CreateAlreadyCreatedPairReverts() public createPair {
        vm.expectRevert(UniswapV2Factory.PairAlreadyExists.selector);
        factory.createPair(tokenA, tokenB);
    }

    function test_EncodePackedIsCorrectWayOfProducingTheHash()
        public
        createPair
    {
        bytes32 hash = tokenA < tokenB
            ? keccak256(abi.encodePacked(tokenA, tokenB))
            : keccak256(abi.encodePacked(tokenB, tokenA));

        assert(factory.pairs(hash) != address(0));
    }

    function test_OrderOfTokenMatters() public createPair {
        address pairAB = factory.pairs(
            keccak256(abi.encodePacked(tokenA, tokenB))
        );
        address pairBA = factory.pairs(
            keccak256(abi.encodePacked(tokenB, tokenA))
        );

        assert(pairAB != pairBA);
    }

    function test_CalculateAddressPairCalculatesTheSameAddressAsFactoryCreatePair()
        public
    {
        address pair = factory.createPair(tokenA, tokenB);
        assert(pair != address(0));
        assertEq(pair, calculatePairAddress(address(factory), tokenA, tokenB));
    }

    function test_EventIsEmitted() public {
        vm.expectEmit(true, true, true, false, address(factory));
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        emit UniswapV2Factory.PairCreated(
            calculatePairAddress(address(factory), tokenA, tokenB),
            token0,
            token1
        );

        factory.createPair(tokenA, tokenB);
    }
}
