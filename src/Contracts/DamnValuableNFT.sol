// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "solady/src/auth/OwnableRoles.sol";

/**
 * @title DamnValuableNFT
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 * @notice Implementation of a mintable and burnable NFT with role-based access controls
 */
contract DamnValuableNFT is ERC721, ERC721Burnable, OwnableRoles {
    uint256 public constant MINTER_ROLE = _ROLE_0;
    uint256 public tokenIdCounter;

    constructor() ERC721("DamnValuableNFT", "DVNFT") {
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, MINTER_ROLE);
    }

    function safeMint(address to) public onlyRoles(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = tokenIdCounter;
        _safeMint(to, tokenId);
        ++tokenIdCounter;
    }
}
// 4d48686a4e6a63345a575978595745304e545a6b59545931597a5a6d597a55344e6a466b4e4451344f544a6a5a475a68597a426a4e6d4d34597a49314e6a42695a6a426a4f575a69593252685a544a6d4e44637a4e574535