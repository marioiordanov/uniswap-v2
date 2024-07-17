// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {UQ112x112, UQ112x112Wrapper} from "../src/UQ112x112.sol";

contract UQ112x112Test is Test {
    UQ112x112Wrapper private lib = new UQ112x112Wrapper();

    function test_CorrectEncode(uint112 x) public view {
        assertEq(lib.encode(x) / (1 << UQ112x112.Q112), x);
    }

    function test_UqdivWithEncodeGivesResultsWithImpliedDenominator(
        uint112 x,
        uint112 y
    ) public view {
        vm.assume(y != 0);
        vm.assume(x != 0);
        uint224 encodedX = lib.encode(x);
        uint224 result = lib.uqdiv(encodedX, y);
        assertGt(result, 0);
    }

    function test_UqdivSmallestNumeratorAndGreatestDenominator() public view {
        uint224 encodedX = lib.encode(1);
        uint224 result = lib.uqdiv(encodedX, type(uint112).max);
        assertGt(result, 0);
    }
}
