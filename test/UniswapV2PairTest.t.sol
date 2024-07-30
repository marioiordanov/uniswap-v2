// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import {console} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {WETH} from "@solady/tokens@v0.0.217/WETH.sol";
import {FixedPointMathLib} from "@solady/utils@v0.0.217/FixedPointMathLib.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts@v5.0.2/token/ERC20/extensions/IERC20Metadata.sol";
import {UQ112x112} from "../src/UQ112x112.sol";

contract InternalFunctionsWrapper is UniswapV2Pair {
    constructor(address token0, address token1) UniswapV2Pair(token0, token1) {}

    function updateWrapper(uint256 balance0, uint256 balance1) external {
        _update(balance0, balance1);
    }

    function getFee(uint256 amount) external pure returns (uint256) {
        return _getFee(amount);
    }
}

contract UniswapV2PairTest is BaseTest {
    using FixedPointMathLib for uint256;
    UniswapV2Pair private pair;
    UniswapV2Factory private factory = new UniswapV2Factory();
    ERC20Mock private usdc = new ERC20Mock("USD COIN", "USDC", 6); // like usdc
    WETH private weth = new WETH();

    address private constant USER1 = address(1);
    address private constant USER2 = address(2);

    function setUp() public {
        // fund addresses with ether
        vm.deal(USER1, 100 ether);
        vm.deal(USER2, 100 ether);

        // get wrapped ether
        vm.prank(USER1);
        weth.deposit{value: USER1.balance}();

        vm.prank(USER2);
        weth.deposit{value: USER2.balance}();

        // _mint tokenA
        uint256 usdcAmount = 100000e6;
        usdc.mint(USER1, usdcAmount);
        usdc.mint(USER2, usdcAmount);

        address pairAddress = calculatePairAddress(
            address(factory),
            address(usdc),
            address(weth)
        );
        // event PairCreated is emitted with the two tokens
        vm.expectEmit(true, true, false, false, pairAddress);
        (address token0, address token1) = orderTokens(
            address(weth),
            address(usdc)
        );
        emit UniswapV2Pair.PairCreated(token0, token1);

        pair = UniswapV2Pair(factory.createPair(address(usdc), address(weth)));
    }

    /// each 1 ETH is equal to 100 USDC
    modifier poolInitialized10ETH1000USDC() {
        vm.startPrank(USER1);
        uint256 usdcAmount = 1000e6;
        uint256 wethAmount = 10 ether;
        usdc.transfer(address(pair), usdcAmount);
        weth.transfer(address(pair), 10 ether);

        vm.expectEmit(true, true, true, false, address(pair));
        // checking data kind of doesnt work
        emit UniswapV2Pair.AddedLiquidity(USER1, usdcAmount, wethAmount);
        pair.mint(
            USER1,
            (usdcAmount * wethAmount).sqrt() - (pair.MINIMUM_LIQUIDITY() * 2)
        );

        (uint112 reserve0, uint112 reserve1) = pair.getReserves();
        assertEq(reserve0, usdcAmount);
        assertEq(reserve1, wethAmount);

        _;
    }

    function test_CorrectLPTokenSymbol() public view {
        string memory token0Symbol = usdc.symbol();
        string memory token1Symbol = weth.symbol();
        string memory expectedSymbol = string(
            abi.encodePacked("LP:", token0Symbol, "-", token1Symbol)
        );

        assertEq(pair.symbol(), expectedSymbol);
    }

    function test_CorrectLPTokenName() public view {
        string memory token0Name = usdc.name();
        string memory token1Name = weth.name();
        string memory expectedName = string(
            abi.encodePacked("Uniswap V2:", token0Name, "-", token1Name)
        );

        assertEq(pair.name(), expectedName);
    }

    function test_UpdateReservesRevertsIfSomeOfTheBalancesAreGreaterThanMaxUint112()
        public
    {
        InternalFunctionsWrapper wrapper = new InternalFunctionsWrapper(
            address(4),
            address(5)
        );
        vm.expectRevert(UniswapV2Pair.ReserveOverflowed.selector);
        wrapper.updateWrapper(uint256(type(uint112).max) + 1, 0);
    }

    function test_UpdateReservesEmitsCorrectEvent() public {
        InternalFunctionsWrapper wrapper = new InternalFunctionsWrapper(
            address(4),
            address(5)
        );
        vm.expectEmit(false, false, false, false, address(wrapper));
        emit UniswapV2Pair.ReservesUpdated();
        wrapper.updateWrapper(1, 1);
    }

    function test_MintingTokensToZeroAddressReverts() public {
        vm.expectRevert(UniswapV2Pair.ReceiverCannotBeZeroAddress.selector);
        pair.mint(address(0), 1);
    }

    function test_MintingZeroLiquidityTokensReverts() public {
        uint256 desiredProduct = pair.MINIMUM_LIQUIDITY() ** 2;
        // deposit 1 token from tokenA
        // the rest of the tokens that satisfy the condition desiredProduct / 1 (tokenA) = desiredProduct (tokenB)
        vm.startPrank(USER1);
        usdc.transfer(address(pair), 1);
        weth.transfer(address(pair), desiredProduct);

        vm.expectRevert(
            UniswapV2Pair.LiquidityTokensMintedCannotBeZero.selector
        );
        pair.mint(USER1, 0);
    }

    function test_MintingLiquidityTokensLessThanMinLiquidityAmountReverts()
        public
    {
        vm.startPrank(USER1);
        usdc.transfer(address(pair), 10);
        weth.transfer(address(pair), 1000000);

        vm.expectRevert(UniswapV2Pair.NotEnoughLiquidityTokensMinted.selector);
        pair.mint(USER1, type(uint256).max);
    }

    function test_FuzzFirstMintingLiquidityTokensIsEqualToSquareRootMinusBurnedLiquidity(
        uint256 usdcAmount,
        uint256 wethAmount
    ) public {
        vm.assume(usdcAmount > 0 && wethAmount > 0);
        vm.assume(wethAmount <= weth.balanceOf(USER1));
        vm.assume(usdcAmount <= usdc.balanceOf(USER1));
        vm.assume((wethAmount * usdcAmount).sqrt() > pair.MINIMUM_LIQUIDITY());

        vm.startPrank(USER1);
        usdc.transfer(address(pair), usdcAmount);
        weth.transfer(address(pair), wethAmount);

        uint256 expectMintedLiquidityTokens = (usdcAmount * wethAmount).sqrt() -
            pair.MINIMUM_LIQUIDITY();

        pair.mint(USER1, expectMintedLiquidityTokens);
        assertEq(pair.balanceOf(USER1), expectMintedLiquidityTokens);
    }

    function test_CorrectAmountOfLPTokensMintedOnInitialLiquiditySupply()
        public
    {
        uint256 tokenAmount = 2e3;
        uint256 expectedAmountOfLPTokens = 1e3;

        vm.startPrank(USER1);
        usdc.transfer(address(pair), tokenAmount);
        weth.transfer(address(pair), tokenAmount);

        pair.mint(USER1, expectedAmountOfLPTokens);
        assertEq(pair.balanceOf(USER1), expectedAmountOfLPTokens);
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());

        assertEq(pair.totalSupply(), (tokenAmount * tokenAmount).sqrt());
        assertEq(pair.reserve0(), tokenAmount);
        assertEq(pair.reserve1(), tokenAmount);
    }

    function test_CorrectAmountOfLPTokensMintedAfterInitialSupplyIsMinted()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER2);
        uint256 reserve0 = pair.reserve0();
        uint256 reserve1 = pair.reserve1();
        uint256 token0Amount = reserve0 / 10;
        uint256 token1Amount = reserve1 / 10;
        uint256 totalSupply = pair.totalSupply();

        if (address(pair.token0()) == address(usdc)) {
            usdc.transfer(address(pair), token0Amount);
            weth.transfer(address(pair), token1Amount);
        } else {
            usdc.transfer(address(pair), token1Amount);
            weth.transfer(address(pair), token0Amount);
        }

        uint256 expectedAmountOfLPTokens = pair.totalSupply() / 10;
        pair.mint(USER2, expectedAmountOfLPTokens);

        assertEq(
            (token0Amount * totalSupply) / reserve0,
            (token1Amount * totalSupply) / reserve1
        );
        assertEq(pair.balanceOf(USER2), expectedAmountOfLPTokens);
        assertEq(pair.reserve0(), reserve0 + token0Amount);
        assertEq(pair.reserve1(), reserve1 + token1Amount);
    }

    function test_IfDifferentRatiosOfTokenToReserveAreProvidedThenTheSmallerIsTheAmountOfLPTokensMinted()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER2);
        uint256 reserve0 = pair.reserve0();
        uint256 reserve1 = pair.reserve1();
        uint256 token0Amount = reserve0 / 10;
        uint256 token1Amount = reserve1;
        uint256 totalSupply = pair.totalSupply();

        if (address(pair.token0()) == address(usdc)) {
            usdc.transfer(address(pair), token0Amount);
            weth.transfer(address(pair), token1Amount);
        } else {
            usdc.transfer(address(pair), token1Amount);
            weth.transfer(address(pair), token0Amount);
        }

        uint256 expectedAmountOfLPTokens = pair.totalSupply() / 10;
        pair.mint(USER2, expectedAmountOfLPTokens);
        assert(
            (token0Amount * totalSupply) / reserve0 <
                (token1Amount * totalSupply) / reserve1
        );
        assertEq(pair.balanceOf(USER2), expectedAmountOfLPTokens);
        assertEq(pair.reserve0(), reserve0 + token0Amount);
        assertEq(pair.reserve1(), reserve1 + token1Amount);
    }

    function test_BurningLiquidityToZeroAddressIsNotAllowed() public {
        vm.expectRevert(UniswapV2Pair.ReceiverCannotBeZeroAddress.selector);
        pair.burn(address(0), 0, 0);
    }

    function test_BurningLiquidityRevertsWhenOutTokensAreZero()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);
        vm.expectRevert(UniswapV2Pair.ZeroTokensOut.selector);
        pair.burn(USER1, 1, 1);
    }

    function test_BurningLiquidityRevertsIfOutTokensAreLessThanMinimumTokensOut()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);
        pair.transfer(address(pair), pair.balanceOf(USER1));
        vm.expectRevert(UniswapV2Pair.MinimumTokensOutCriteriaNotMet.selector);
        pair.burn(USER1, type(uint256).max, type(uint256).max);
    }

    function test_BurningLiquiditySendsCorrectAmountOfTokens() public {
        vm.startPrank(USER1);
        // try to get 2k total liquidity tokens
        // => sqrt(x) = 2k => 2000^2 = 4e6
        // 100eth and 40000 usdc
        // pool has 2k shares
        // 1k shares for 0 address
        // 1k shares for USER1
        // USER1 burns .5 shares of his total => 500 shares

        uint256 initialUsdcBalance = usdc.balanceOf(USER1);
        uint256 initialWethBalance = weth.balanceOf(USER1);
        uint256 usdcAmount = 40000;
        uint256 wethAmount = 100;

        usdc.transfer(address(pair), usdcAmount);
        weth.transfer(address(pair), wethAmount);
        pair.mint(USER1, 1e3);

        uint112 inititalReserve0 = pair.reserve0();
        uint112 inititalReserve1 = pair.reserve1();

        uint256 lpShares = pair.balanceOf(USER1);
        uint256 sharesToBurn = lpShares / 2;
        pair.transfer(address(pair), sharesToBurn);
        uint256 usdcToReceive = (usdc.balanceOf(address(pair)) * sharesToBurn) /
            pair.totalSupply();
        uint256 wethToReceive = (weth.balanceOf(address(pair)) * sharesToBurn) /
            pair.totalSupply();
        (uint256 amount0Out, uint256 amount1Out) = pair.burn(
            USER1,
            (usdcAmount * sharesToBurn) / pair.totalSupply(),
            (wethAmount * sharesToBurn) / pair.totalSupply()
        );

        assertEq(
            usdc.balanceOf(USER1),
            initialUsdcBalance - usdcAmount + usdcToReceive
        );

        assertEq(
            weth.balanceOf(USER1),
            initialWethBalance - wethAmount + wethToReceive
        );

        assertEq(inititalReserve0 - uint112(amount0Out), pair.reserve0());
        assertEq(inititalReserve1 - uint112(amount1Out), pair.reserve1());
    }

    function test_BurningLiquidityEmitsCorrectEvent()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);
        uint256 liqudityTokensToBurn = pair.balanceOf(USER1);
        pair.transfer(address(pair), liqudityTokensToBurn);
        vm.expectEmit(true, false, false, false, address(pair));
        emit UniswapV2Pair.LiquidityBurned(liqudityTokensToBurn, 0, 0);
        pair.burn(USER1, 0, 0);
    }

    function test_SwappingAmountBiggerThanReserveShouldRevert()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);

        vm.expectRevert(UniswapV2Pair.NotEnoughLiquidityForSwap.selector);
        pair.swap(type(uint256).max, 0, USER1, 0);
    }

    function test_SwappingHaveToHoldTheKEquation()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);

        (uint112 reserve0, uint112 reserve1) = pair.getReserves();
        uint256 priceOfToken1InToken0 = (reserve0 * 1 ether) / reserve1;
        usdc.transfer(address(pair), priceOfToken1InToken0);

        vm.expectRevert(UniswapV2Pair.KEquationDoesntHeld.selector);
        pair.swap(0, 1 ether, USER1, 0);
    }

    function test_SwappingShouldRevertWhenUserOverpays()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);

        (uint112 reserve0, uint112 reserve1) = pair.getReserves();

        uint256 usdcInAfterFee = 100 * 10 ** usdc.decimals();
        uint256 usdcInBeforeFee = 1 + (usdcInAfterFee * 1000) / 997;

        uint256 wethOut = reserve1 -
            ((reserve0 * reserve1) / (reserve0 + usdcInAfterFee));

        usdc.transfer(address(pair), usdcInBeforeFee);
        vm.expectRevert(UniswapV2Pair.OverpayedForSwap.selector);
        pair.swap(0, wethOut, USER1, 0);
    }

    /// Swaps with 0.01% tolerance
    function test_Swapping1000UsdcAfterFeeShouldReceiveLessThanQuotedAmount()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);

        (uint112 reserve0, uint112 reserve1) = pair.getReserves();

        // 1000.000000 usdc
        // 10.000000000000000000 weth

        // amountIn = x - 0.3%x => 0.997x
        uint256 usdcInAfterFee = 100 * 10 ** usdc.decimals();
        uint256 usdcInBeforeFee = 1 + (usdcInAfterFee * 1000) / 997;

        // xa = xb - 0.3xb

        // xb = xa * 1000 - 3xa

        // x * y = k
        // (x + xa)(y - y1) >= k
        // (x + 0.997xa)(y - y1) >= k
        // y1 = y - k / (x + 0.997xa)
        // 100 usdc in
        // y1 = 10e18 - k/ (x + 0.997*100)
        uint256 wethOut = reserve1 -
            ((reserve0 * reserve1) / (reserve0 + usdcInAfterFee));

        // x*y = k
        // (x + x1)(y-y1) >= k
        // y - y1 = k / (x + x1)
        // y1 = y - k / (x + x1)
        // 10000000000000000000000000000000000
        //  9999999993581818181718181818246000

        usdc.transfer(address(pair), usdcInBeforeFee);
        pair.swap(0, wethOut, USER1, 1);
    }

    function test_SwappingWithMoreThan10000BasisPointsShouldRevert() public {
        vm.expectRevert(UniswapV2Pair.InvalidBasisPoints.selector);
        pair.swap(1, 1, USER1, 10001);
    }

    function test_SwappingWithAmount0OutAndAmount0InIsSuccessful()
        public
        poolInitialized10ETH1000USDC
    {
        vm.startPrank(USER1);
        uint256 usdcInitialBalance = usdc.balanceOf(USER1);
        uint256 wethInitialBalance = weth.balanceOf(USER1);
        uint256 usdcOut = 1e6;
        uint256 wethOut = 1e18;

        // x*y >=k
        uint256 usdcIn = 1 + (usdcOut * 1000) / 997;

        uint256 wethIn = 1 + (wethOut * 1000) / 997;

        usdc.transfer(address(pair), usdcIn);
        weth.transfer(address(pair), wethIn);
        pair.swap(usdcOut, wethOut, USER1);

        assertEq(usdc.balanceOf(USER1), usdcInitialBalance - usdcIn + usdcOut);
        assertEq(weth.balanceOf(USER1), wethInitialBalance - wethIn + wethOut);
    }

    function test_PriceAtInitialMintingIsNotBeingAccumulated()
        public
        poolInitialized10ETH1000USDC
    {
        assert(pair.price0Cumulative() == 0);
        assert(pair.price1Cumulative() == 0);
    }

    function test_Price3SecondsAfterInitialMintingAccumulatesCorrectly()
        public
        poolInitialized10ETH1000USDC
    {
        uint256 secondsPassed = 3;
        vm.warp(block.timestamp + secondsPassed);

        vm.startPrank(USER2);
        usdc.transfer(address(pair), 100e6);
        weth.transfer(address(pair), 1e18);

        pair.mint(USER2, 1);

        // price 1 => 1000 usdc / 10 weth => 1weth = 100 usdc
        // price 0 => 10 weth / 1000 usdc => 1usdc = 0.01 weth

        // check price 0 cumulative
        // have to be 3*10e18/1000e6 / 2**112
        uint256 expectedPrice0Cumulative = (secondsPassed * 10e18) / 1000e6;
        // then have to be checked against data from contract, with removed implied denominator
        assertEq(
            expectedPrice0Cumulative,
            pair.price0Cumulative() >> UQ112x112.Q112
        );

        // for price 1 implied denominator must not be removed, because in the denominator there are more decimals
        uint256 expectedPrice1Cumulative = 3 *
            ((1000e6 << UQ112x112.Q112) / 10e18);
        assertEq(expectedPrice1Cumulative, pair.price1Cumulative());
    }

    function test_GetFeeRoundsUp() public {
        InternalFunctionsWrapper wrapper = new InternalFunctionsWrapper(
            address(4),
            address(5)
        );
        uint256 amount = 3333;
        uint256 fee = wrapper.getFee(amount);
        uint256 expectedFee = 10;
        assertEq(fee, expectedFee);
    }
}
