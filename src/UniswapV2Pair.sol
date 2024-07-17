// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {ERC20} from "@solady/tokens@v0.0.217/ERC20.sol";
import {FixedPointMathLib} from "@solady/utils@v0.0.217/FixedPointMathLib.sol";

contract UniswapV2Pair is ERC20 {
    using FixedPointMathLib for uint256;
    enum ReentrancyState {
        NON_ENTERED,
        ENTERED
    }

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    // 0.3% fee
    uint256 public constant FEE_NUMERATOR = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    address public immutable token0;
    address public immutable token1;

    uint112 public reserve0;
    uint112 public reserve1;

    ReentrancyState private state;

    // events
    event PairCreated(address indexed token0, address indexed token1);
    event AddedLiquidity(
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );
    event ReservesUpdated();

    // errors
    error ReentrantCall();
    error LiquidityTokensMintedCannotBeZero();
    error NotEnoughLiquidityTokensMinted();
    error ReserveOverflowed();
    error ReceiverCannotBeZeroAddress();

    // modifiers
    modifier nonReentrant() {
        if (state == ReentrancyState.ENTERED) {
            revert ReentrantCall();
        }
        state = ReentrancyState.ENTERED;
        _;
        state = ReentrancyState.NON_ENTERED;
    }

    // functions (order):
    // 1. visibility (external, public, internal, private)
    // 2. payable, non-payable, view, pure

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;

        emit PairCreated(_token0, _token1);
    }

    /// @notice Provides liquidity to the Uniswap V2 pair
    /// @dev Reverts if minted tokens are less than minLPTokensOut
    /// @param _to the address that will receive the LP tokens
    /// @param _minLiquidityMinted the minimum amount of LP tokens that should be minted
    function mint(
        address _to,
        uint256 _minLiquidityMinted
    ) external returns (uint256 liquidity) {
        if (_to == address(0)) {
            revert ReceiverCannotBeZeroAddress();
        }
        uint256 currentBalance0 = ERC20(token0).balanceOf(address(this));
        uint256 currentBalance1 = ERC20(token1).balanceOf(address(this));
        uint256 balance0In = currentBalance0 - reserve0;
        uint256 balance1In = currentBalance1 - reserve1;

        uint256 totalSupply = totalSupply();

        if (totalSupply == 0) {
            liquidity = (balance0In * balance1In).sqrt() - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = FixedPointMathLib.min(
                (balance0In * totalSupply) / reserve0,
                (balance1In * totalSupply) / reserve1
            );
        }

        if (liquidity == 0) {
            revert LiquidityTokensMintedCannotBeZero();
        }

        if (liquidity < _minLiquidityMinted) {
            revert NotEnoughLiquidityTokensMinted();
        }

        _mint(_to, liquidity);
        _update(currentBalance0, currentBalance1);
        emit AddedLiquidity(msg.sender, balance0In, balance1In);
    }

    function name() public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "Uniswap V2:",
                    ERC20(token0).name(),
                    "-",
                    ERC20(token1).name()
                )
            );
    }

    function symbol() public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "LP:",
                    ERC20(token0).symbol(),
                    "-",
                    ERC20(token1).symbol()
                )
            );
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        unchecked {
            if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
                revert ReserveOverflowed();
            }
            reserve0 = uint112(balance0);
            reserve1 = uint112(balance1);

            emit ReservesUpdated();
        }
    }
}
