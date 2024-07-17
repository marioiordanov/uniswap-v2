// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))

// range: [0, 2**112 - 1]
// resolution: 1 / 2**112

library UQ112x112 {
    uint224 constant Q112 = 112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) << Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

contract UQ112x112Wrapper {
    function encode(uint112 x) public pure returns (uint224) {
        return UQ112x112.encode(x);
    }

    function uqdiv(uint224 x, uint112 y) public pure returns (uint224 z) {
        return UQ112x112.uqdiv(x, y);
    }
}
