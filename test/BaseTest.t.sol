// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";

abstract contract BaseTest is Test {
    // exclude from coverage
    function test() public {}

    // calculate the CREATE2 address for a pair without making any external calls
    function calculatePairAddress(
        address _factory,
        address _tokenA,
        address _tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = orderTokens(_tokenA, _tokenB);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes memory bytecode = abi.encodePacked(
            type(UniswapV2Pair).creationCode,
            abi.encode(token0, token1)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), _factory, salt, keccak256(bytecode))
        );

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    // order tokens based on its uint160 value
    function orderTokens(
        address _tokenA,
        address _tokenB
    ) internal pure returns (address token0, address token1) {
        return _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }
}
