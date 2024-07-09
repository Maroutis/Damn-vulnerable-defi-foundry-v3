// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./ERC20-0.6.sol";

/**
 * @title DamnValuableToken
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract DamnValuableToken is ERC20 {
    constructor() public ERC20("DamnValuableToken", "DVT", 18) {
        _mint(msg.sender, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }
}