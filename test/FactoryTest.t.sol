// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {Factory, FactoryAssembly} from "../src/Factory.sol";

contract FactoryTest is Test {
    Factory public factory;
    FactoryAssembly public factoryAssembly;
    address private OWNER = makeAddr("owner");
    uint256 private constant SALT = 1;
    uint256 private constant FOO = 1;

    function setUp() public {
        factory = new Factory();
        factoryAssembly = new FactoryAssembly();
    }

    function testEncode() public {
        console.logBytes(abi.encodePacked(address(1)));
        console.logBytes(abi.encode(address(1)));
    }

    function testAddress() public {
        bytes memory bytecode = factoryAssembly.getBytecode(OWNER, FOO);
        console.log(factoryAssembly.getAddress(bytecode, SALT));
        factoryAssembly.deploy(bytecode, SALT);
    }

    function testAddressFactory() public {
        console.log(factory.deploy(OWNER, FOO, SALT));
    }

    function testAddressFactory2() public {
        console.log(factory.deploy2(OWNER, FOO, bytes32(SALT)));
    }

    function testBytes() public {
        bytes memory bytecode = abi.encodePacked(uint8(1), uint8(2), uint8(3));
        assembly {
            log0(0x00, 0xe0)
            log0(bytecode, 0x40)
        }
        /*
        0x
        00 0000000000000000000000000000000000000000000000000000000000000000
        20 0000000000000000000000000000000000000000000000000000000000000000
        40 00000000000000000000000000000000000000000000000000000000000000a3
        60 0000000000000000000000000000000000000000000000000000000000000000
        80 0000000000000000000000000000000000000000000000000000000000000003
        a0 0102030000000000000000000000000000000000000000000000000000000000
        c0 0000000000000000000000000000000000000000000000000000000000000000
        */
        uint256[] memory arr = new uint256[](2);
        arr[0] = 11;
        arr[1] = 21;
        assembly {
            log0(0x00, 0x180)
        }

        /*
        0x
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000000103
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000000003
        0102030000000000000000000000000000000000000000000000000000000000000002
        000000000000000000000000000000000000000000000000000000000000000b
        0000000000000000000000000000000000000000000000000000000000000015
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000000000
        0000000000000000000000000000000000000000000000000000000000
        */
        console.logBytes(bytecode);
        bytes memory bytecode2;
        uint256 a;

        assembly {
            log0(0x40, 0xa0)
            let x := add(bytecode, 0x20)
            a := add(bytecode, 0x20)
            bytecode2 := mload(0x40)
        }
        // 0x
        // 0x40 0000000000000000000000000000000000000000000000000000000000000127
        // 0x60 0000000000000000000000000000000000000000000000000000000000000000
        // 0x80 0000000000000000000000000000000000000000000000000000000000000003
        // 0xa0 0102030000000000000000000000000000000000000000000000000000000000
        // 0xc0 0000640be77f5600000000000000000000000000000000000000000000000000

        console.logBytes(bytecode2);
        console.logBytes(abi.encodePacked(a));
    }

    function testSize() public {}
}
