// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import {UniswapV2Pair} from "./UniswapV2Pair.sol";

contract UniswapV2Factory {
    // state vars
    mapping(bytes32 hash => address pair) public pairs;

    // events
    event PairCreated(
        address indexed pair,
        address indexed token0,
        address indexed token1
    );
    // errors
    error PairAlreadyExists();
    error ZeroAddressNotAllowed();
    error AddressesInPairCannotBeTheSame();

    // modifiers

    // functions (order):
    // 1. visibility (external, public, internal, private)
    // 2. payable, non-payable, view, pure

    function createPair(
        address _tokenA,
        address _tokenB
    ) external returns (address pair) {
        if (_tokenA == _tokenB) {
            revert AddressesInPairCannotBeTheSame();
        }

        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        if (token0 == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        if (pairs[salt] != address(0)) {
            revert PairAlreadyExists();
        }

        bytes memory bytecode = abi.encodePacked(
            type(UniswapV2Pair).creationCode, // contract creation code
            abi.encode(token0, token1) // constructor arguments
        );

        assembly {
            pair := create2(
                0, // wei sent with current call
                // Actual code starts after skipping the first 32 bytes
                add(bytecode, 0x20),
                mload(bytecode), // Load the size of code contained in the first 32 bytes
                salt // Salt from function arguments
            )
        }

        pairs[salt] = pair;
        emit PairCreated(pair, token0, token1);
        return pair;
    }

    function getPair(
        address _tokenA,
        address _tokenB
    ) public view returns (address) {
        (address token0, address token1) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);

        // encodePacked can be used instead of abi.encode, because hash collision vulnerability is present when there are arrays
        bytes32 hash = keccak256(abi.encodePacked(token0, token1));
        return pairs[hash];
    }
}
