1. cumulative price should increase, even if there is an overflow
2. when minting liquidity, total supply increases and amount in pools increases
3. x*y >= k
4. Total supply of the pool doesnt change if none of the methods (mint, burn) is called
5. Initial liquidity have to be minted
6. AmountIn used for swapping is always less that the actual amountIn by 0.3%
7. With each swap K increases if fee is not zero
8. K can change if none of the methods (mint, burn, swap) is called
9. Redeeming tokens from the pool have to give to the user the fair share of the fees accumulated
