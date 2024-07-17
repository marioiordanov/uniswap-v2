// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

struct Fraction {
    uint256 numerator;
    uint256 denominator;
}

library FractionHelper {
    // 33 is the maximum precision possible due to 2^112 being ~ 5e33
    uint8 internal constant MAX_PRECISION = 33;

    function test() public {}

    error PrecisionTooHigh(uint8 precision, uint8 maxPrecision);

    function create(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (Fraction memory fraction) {
        uint256 gcd = calculateGCD(numerator, denominator);
        // reduce the fraction
        if (gcd > 1) {
            fraction.numerator = numerator / gcd;
            fraction.denominator = denominator / gcd;
        } else {
            fraction.numerator = numerator;
            fraction.denominator = denominator;
        }
    }

    function add(
        Fraction memory x,
        Fraction memory y
    ) internal pure returns (Fraction memory z) {
        // calculate LCM of denominators
        // multiply each numerator by LCM/denominator
        // add the numerators
        // new denominator is LCM
        // find gcd of the new numerator and denominator
        // divide numerator and denominator by gcd

        // 6/7 + 13/42 = 36/42 + 13/42 = 49/42 => 7/6

        uint256 lcm = calculateLCM(x.denominator, y.denominator);
        uint256 xNumerator = (lcm / x.denominator) * x.numerator;
        uint256 yNumerator = (lcm / y.denominator) * y.numerator;

        z.numerator = xNumerator + yNumerator;
        z.denominator = lcm;
        uint256 gcd = calculateGCD(z.numerator, z.denominator);
        z.numerator = z.numerator / gcd;
        z.denominator = z.denominator / gcd;
    }

    function multiply(
        Fraction memory x,
        Fraction memory y
    ) internal pure returns (Fraction memory z) {
        z.numerator = x.numerator * y.numerator;
        z.denominator = x.denominator * y.denominator;

        uint256 gcd = calculateGCD(z.numerator, z.denominator);
        if (gcd > 1) {
            z.numerator = z.numerator / gcd;
            z.denominator = z.denominator / gcd;
        }
        // // can be optimized by reducing the fraction before multiplications
        // uint256 gcd = calculateGCD(x.numerator, y.denominator);
        // if (gcd > 1) {
        //     z.numerator = x.numerator / gcd;
        //     z.denominator = y.denominator / gcd;
        // }

        // gcd = calculateGCD(y.numerator, x.denominator);
        // if (gcd > 1) {
        //     z.numerator = (y.numerator / gcd) * z.numerator;
        //     z.denominator = (x.denominator / gcd) * z.denominator;
        // }
    }

    function calculateLCM(uint256 a, uint256 b) public pure returns (uint256) {
        return _calculateLCM(a, b, calculateGCD(a, b));
    }

    function _calculateLCM(
        uint256 a,
        uint256 b,
        uint256 gcd
    ) internal pure returns (uint256) {
        require(a > 0 && b > 0, "Both numbers should be greater than 0");
        return (a * b) / gcd;
    }

    function calculateGCD(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        while (b != 0) {
            uint256 temp = b;
            b = a % b;
            a = temp;
        }
        return a;
    }

    function areDivisible(uint256 a, uint256 b) internal pure returns (bool) {
        if (a > b) return a % b == 0;
        return b % a == 0;
    }

    function toDecimalWithPrecision(
        Fraction memory x,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (MAX_PRECISION < decimals) {
            revert PrecisionTooHigh(decimals, MAX_PRECISION);
        }

        return (x.numerator * uint256(10 ** decimals)) / x.denominator;
    }
}
