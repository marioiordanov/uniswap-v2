// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import {console} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {WETH} from "@solady/tokens@v0.0.217/WETH.sol";
import {FixedPointMathLib} from "@solady/utils@v0.0.217/FixedPointMathLib.sol";
import {BaseTest} from "./BaseTest.t.sol";

contract InternalFunctionsWrapper is UniswapV2Pair {
    constructor(address token0, address token1) UniswapV2Pair(token0, token1) {}

    function updateWrapper(uint256 balance0, uint256 balance1) external {
        _update(balance0, balance1);
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

        if (pair.token0() == address(usdc)) {
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

        if (pair.token0() == address(usdc)) {
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
}
