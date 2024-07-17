// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Fraction, FractionHelper} from "../src/Fraction.sol";

contract FractionTest is Test {
    function setUp() public {}

    function testLCM() public view {
        Fraction memory a = Fraction(6, 7);
        Fraction memory b = Fraction(13, 42);
        Fraction memory c = FractionHelper.add(a, b);

        console.log(c.numerator);
        console.log(c.denominator);
    }

    function testPrecision() public view {
        console.log(uint256(4) << 1);
        uint256 gcd = FractionHelper.calculateGCD(13, 100);
        // reduce the fraction
        // if (gcd > 1) {
        //     fraction.numerator = numerator / gcd;
        //     fraction.denominator = denominator / gcd;
        // } else {
        //     fraction.numerator = numerator;
        //     fraction.denominator = denominator;
        // }
        console.log(
            FractionHelper.toDecimalWithPrecision(
                FractionHelper.create(13, 100),
                10
            )
        );
    }
}
