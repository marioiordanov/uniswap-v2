// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;
import {ERC20} from "@solady/tokens@v0.0.217/ERC20.sol";

contract ERC20Mock is ERC20 {
    string private tokenName;
    string private tokenSymbol;
    uint8 private tokenDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        tokenName = _name;
        tokenSymbol = _symbol;
        tokenDecimals = _decimals;
    }

    // for excluding from coverage report
    function test() public {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return tokenName;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return tokenSymbol;
    }

    /// @dev Returns the decimals places of the token.
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}
