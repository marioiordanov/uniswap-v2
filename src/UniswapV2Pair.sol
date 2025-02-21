// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {ERC20} from "@solady/tokens@v0.0.217/ERC20.sol";
import {FixedPointMathLib} from "@solady/utils@v0.0.217/FixedPointMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts@v5.0.2/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts@v5.0.2/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@v5.0.2/token/ERC20/extensions/IERC20Metadata.sol";
import {UQ112x112} from "./UQ112x112.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts@v5.0.2/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts@v5.0.2/interfaces/IERC3156FlashBorrower.sol";

contract UniswapV2Pair is ERC20, IERC3156FlashLender {
    using FixedPointMathLib for uint256;
    using UQ112x112 for uint224;
    // reentrancy state enum the first value is for gas optimizations
    // to avoid setting in each function call the state from 0 to non zero
    enum ReentrancyState {
        NON_USED_VALUE_FOR_GAS_OPTIMIZATION, // 0
        NON_ENTERED, // 1
        ENTERED // 2
    }

    struct SwapCalculations {
        uint256 balance0;
        uint256 balance1;
        uint256 amount0In;
        uint256 amount1In;
    }

    uint16 public constant BASIS_POINTS_UPPER_BOUND = 10_000;
    uint16 public constant DEFAULT_BASIS_POINTS_TOLERANCE = 100;
    uint256 private constant TIMESTAMP_MODULO_ARGUMENT = 1 << 32; // equal to 2^32
    bytes32 private constant FLASH_BORROWER_ON_FLASH_LOAN_EXPECTED_RESULT =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    // 0.3% fee
    uint256 public constant SWAP_FEE_NUMERATOR = 3;
    uint256 public constant SWAP_FEE_DENOMINATOR = 1000;

    // state variables
    // slot 0
    ReentrancyState private state;
    IERC20 public immutable token0;
    // slot 1
    IERC20 public immutable token1;

    // slot 2
    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public lastUpdatedBlocktimestamp;

    // slot 3
    uint256 public price0Cumulative;
    // slot 4
    uint256 public price1Cumulative;

    // events
    event PairCreated(address indexed token0, address indexed token1);
    event AddedLiquidity(
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );
    event ReservesUpdated();
    event LiquidityBurned(
        uint256 liquidityTokensBurned,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event Swap(
        address indexed sender,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount1In,
        uint256 amount0In,
        address indexed to
    );

    // errors
    error ReentrantCall();
    error LiquidityTokensMintedCannotBeZero();
    error NotEnoughLiquidityTokensMinted();
    error ReserveOverflowed();
    error ReceiverCannotBeZeroAddress();
    error ZeroTokensOut();
    error MinimumTokensOutCriteriaNotMet();
    error NotEnoughLiquidityForSwap();
    error KEquationDoesntHeld();
    error OverpayedForSwap();
    error InvalidBasisPoints();
    error TokenNotSupportedForFlashLoan();
    error FlashLoanReceiverDoesntImplementOnFlashLoan();

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
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        emit PairCreated(_token0, _token1);
    }

    /// @notice Swap with 1% tolerance
    /// @dev Uses default value for tolerance basis points (1 basis points is 1/100 of 1%)
    /// @param _amount0Out The amount of token0 to be sent to user
    /// @param _amount1Out The amount of token1 to be sent to user
    /// @param _to The user that will receive the tokens
    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to
    ) external {
        _swap(_amount0Out, _amount1Out, _to, DEFAULT_BASIS_POINTS_TOLERANCE);
    }

    /// @notice Swap with user specicified tolerance
    /// @dev Tolerance basis points cant be more than BASIS_POINTS_UPPER_BOUND
    /// @param _amount0Out The amount of token0 to be sent to user
    /// @param _amount1Out The amount of token1 to be sent to user
    /// @param _to The user that will receive the tokens
    /// @param _toleranceBasisPoints Percentage for tolerance in the swap, measured in basis points (1 basis point = 1/100 of 1%)
    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        uint16 _toleranceBasisPoints
    ) external {
        _swap(_amount0Out, _amount1Out, _to, _toleranceBasisPoints);
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override nonReentrant returns (bool) {
        uint256 amount0Out = 0;
        uint256 amount1Out = 0;
        address receiverAddress = address(receiver);
        if (token == address(token0)) {
            amount0Out = amount;
        } else if (token == address(token1)) {
            amount1Out = amount;
        } else {
            revert TokenNotSupportedForFlashLoan();
        }

        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        {
            // calculate the fee
            uint256 fee = _getFee(amount);

            _swapSendTokens(
                amount0Out,
                amount1Out,
                receiverAddress,
                _reserve0,
                _reserve1
            );

            // send amount of token to receiver
            if (
                receiver.onFlashLoan(msg.sender, token, amount, fee, data) !=
                FLASH_BORROWER_ON_FLASH_LOAN_EXPECTED_RESULT
            ) {
                revert FlashLoanReceiverDoesntImplementOnFlashLoan();
            }

            // transferFrom tokens back to the pair

            SafeERC20.safeTransferFrom(
                IERC20(token),
                receiverAddress,
                address(this),
                amount + fee
            );

            SwapCalculations memory calculations = _doSwap(
                _reserve0,
                _reserve1,
                amount0Out,
                amount1Out,
                false,
                0
            );

            _update(calculations.balance0, calculations.balance1);
            emit Swap(
                msg.sender,
                amount0Out,
                amount1Out,
                calculations.amount1In,
                calculations.amount0In,
                receiverAddress
            );
        }

        return true;
    }

    /// @notice Provides liquidity to the Uniswap V2 pair. User have to send the tokens to the pair contract as part of a transaction
    /// @dev Reverts if minted tokens are less than minLPTokensOut
    /// @param _to the address that will receive the LP tokens
    /// @param _minLiquidityMinted the minimum amount of LP tokens that should be minted
    function mint(
        address _to,
        uint256 _minLiquidityMinted
    ) external nonReentrant returns (uint256 liquidity) {
        if (_to == address(0)) {
            revert ReceiverCannotBeZeroAddress();
        }
        uint256 currentBalance0 = token0.balanceOf(address(this));
        uint256 currentBalance1 = token1.balanceOf(address(this));
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

    /// @notice User burns LP tokens to withdraw the underlying tokens. User have to send the LP tokens to the pair contract as part of a transaction
    /// @dev Reverts if one of the amounts of tokens received is less than the minimum amount
    /// @param _to the address which is going to receive tokens from reserve0 and reserve1
    /// @param _minimumTokens0Out the minimum amount of token0 that should be received
    /// @param _minimumTokens1Out the minimum amount of token1 that should be received
    /// @return amount0Out the amount of tokens0 received due to the burning of LP tokens
    /// @return amount1Out the amount of tokens1 received due to the burning of LP tokens
    function burn(
        address _to,
        uint256 _minimumTokens0Out,
        uint256 _minimumTokens1Out
    ) external nonReentrant returns (uint256 amount0Out, uint256 amount1Out) {
        if (_to == address(0)) {
            revert ReceiverCannotBeZeroAddress();
        }
        uint256 totalSupplyLiquidityTokens = totalSupply();
        uint256 currentBalance0 = token0.balanceOf(address(this));
        uint256 currentBalance1 = token1.balanceOf(address(this));
        uint256 liquidityTokens = balanceOf(address(this));

        amount0Out =
            (liquidityTokens * currentBalance0) /
            totalSupplyLiquidityTokens;
        amount1Out =
            (liquidityTokens * currentBalance1) /
            totalSupplyLiquidityTokens;

        if (amount0Out == 0 || amount1Out == 0) {
            revert ZeroTokensOut();
        }

        if (
            amount0Out < _minimumTokens0Out || amount1Out < _minimumTokens1Out
        ) {
            revert MinimumTokensOutCriteriaNotMet();
        }

        _burn(address(this), liquidityTokens);
        SafeERC20.safeTransfer(token0, _to, amount0Out);
        SafeERC20.safeTransfer(token1, _to, amount1Out);

        _update(
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        emit LiquidityBurned(liquidityTokens, amount0Out, amount1Out);
    }

    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        if (token == address(token0)) {
            return reserve0;
        } else if (token == address(token1)) {
            return reserve1;
        } else {
            return 0;
        }
    }

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
        if (token != address(token0) && token != address(token1)) {
            revert TokenNotSupportedForFlashLoan();
        }

        return _getFee(amount);
    }

    function getReserves() public view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    /// @notice Returns the name of the token that represents the share of the pool
    /// ERC20 standard function - name
    function name() public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "Uniswap V2:",
                    IERC20Metadata(address(token0)).name(),
                    "-",
                    IERC20Metadata(address(token1)).name()
                )
            );
    }

    /// @notice Returns the symbol of the token that represents the share of the pool
    /// ERC20 standard function - symbol
    function symbol() public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "LP:",
                    IERC20Metadata(address(token0)).symbol(),
                    "-",
                    IERC20Metadata(address(token1)).symbol()
                )
            );
    }

    function _update(uint256 _balance0, uint256 _balance1) internal {
        unchecked {
            if (
                _balance0 > type(uint112).max || _balance1 > type(uint112).max
            ) {
                revert ReserveOverflowed();
            }

            uint32 blockTimestamp = uint32(
                block.timestamp % TIMESTAMP_MODULO_ARGUMENT
            );

            uint32 timeElapsed = blockTimestamp - lastUpdatedBlocktimestamp;

            // to avoid accumulating price when at first there was no liquidity
            if (timeElapsed > 0 && reserve0 > 0 && reserve1 > 0) {
                price0Cumulative +=
                    UQ112x112.encode(reserve1).uqdiv(reserve0) *
                    timeElapsed;
                price1Cumulative +=
                    UQ112x112.encode(reserve0).uqdiv(reserve1) *
                    timeElapsed;
            }

            reserve0 = uint112(_balance0);
            reserve1 = uint112(_balance1);
            // it will always be less than 2^32 due to modulo division
            lastUpdatedBlocktimestamp = blockTimestamp;

            emit ReservesUpdated();
        }
    }

    function _swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        uint256 _toleranceBasisPoints
    ) internal nonReentrant {
        if (_toleranceBasisPoints > BASIS_POINTS_UPPER_BOUND) {
            revert InvalidBasisPoints();
        }
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        _swapSendTokens(_amount0Out, _amount1Out, _to, _reserve0, _reserve1);

        SwapCalculations memory calculations = _doSwap(
            _reserve0,
            _reserve1,
            _amount0Out,
            _amount1Out,
            true,
            _toleranceBasisPoints
        );

        _update(calculations.balance0, calculations.balance1);
        emit Swap(
            msg.sender,
            _amount0Out,
            _amount1Out,
            calculations.amount1In,
            calculations.amount0In,
            _to
        );
    }

    /// @notice Calculates the fee for the flash loan
    /// @dev Rounds up
    /// @dev calculates the fee as if the amount + fee is to be reduced by 0.3%
    function _getFee(uint256 _amount) internal pure returns (uint256) {
        uint256 product = _amount * SWAP_FEE_DENOMINATOR;

        return
            product /
            (SWAP_FEE_DENOMINATOR - SWAP_FEE_NUMERATOR) +
            (
                product % (SWAP_FEE_DENOMINATOR - SWAP_FEE_NUMERATOR) == 0
                    ? 0
                    : 1
            ) -
            _amount;
    }

    function _swapSendTokens(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        if (_amount0Out > _reserve0 || _amount1Out > _reserve1) {
            revert NotEnoughLiquidityForSwap();
        }

        if (_amount0Out > 0) {
            SafeERC20.safeTransfer(token0, _to, _amount0Out);
        }

        if (_amount1Out > 0) {
            SafeERC20.safeTransfer(token1, _to, _amount1Out);
        }
    }

    function _doSwap(
        uint112 _reserve0,
        uint112 _reserve1,
        uint256 _amount0Out,
        uint256 _amount1Out,
        bool checkTolerance,
        uint256 _toleranceBasisPoints
    ) private view returns (SwapCalculations memory calculations) {
        // stack too deep error
        {
            calculations.balance0 = token0.balanceOf(address(this));
            calculations.balance1 = token1.balanceOf(address(this));

            calculations.amount0In = calculations.balance0 >
                _reserve0 - _amount0Out
                ? calculations.balance0 - (_reserve0 - _amount0Out)
                : 0;
            calculations.amount1In = calculations.balance1 >
                _reserve1 - _amount1Out
                ? calculations.balance1 - (_reserve1 - _amount1Out)
                : 0;

            uint256 balance0Adjusted = calculations.balance0 *
                SWAP_FEE_DENOMINATOR -
                calculations.amount0In *
                SWAP_FEE_NUMERATOR;

            uint256 balance1Adjusted = calculations.balance1 *
                SWAP_FEE_DENOMINATOR -
                calculations.amount1In *
                SWAP_FEE_NUMERATOR;

            uint256 amountInWithFeeProduct = balance0Adjusted *
                balance1Adjusted;

            uint256 currentK = _reserve0 *
                _reserve1 *
                SWAP_FEE_DENOMINATOR *
                SWAP_FEE_DENOMINATOR;

            if (amountInWithFeeProduct < currentK) {
                revert KEquationDoesntHeld();
            }

            if (
                checkTolerance &&
                amountInWithFeeProduct >
                (currentK *
                    (BASIS_POINTS_UPPER_BOUND + _toleranceBasisPoints)) /
                    BASIS_POINTS_UPPER_BOUND
            ) {
                revert OverpayedForSwap();
            }

            return calculations;
        }
    }
}
