// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IPropertyValidator.sol";
import "../interfaces/IERC20.sol";

library Orders {

    struct NFTListing {
        uint8 tokenType; // 0 is ERC721, 1 is ERC1155
        uint8 status; // 0 is Active, 1 is Filled, 2 is Cancelled
        uint64 expiry;
        uint160 nft;
        address lister;
        address taker;
        uint256 nftId;
        uint256 paymentAmount;
    }

    struct TokenListing {
        uint8 status; // 0 is Active, 1 is Filled, 2 is Cancelled
        uint64 expiry;
        uint160 token;
        uint256 tokenAmount;
        uint256 paymentAmount;
        address lister;
        address taker;
    }

    function getTokenHash(address nft, uint256 nftId) internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(nft, nftId));
    }

    function getNFTListingHash(address sender, address nft, uint256 nftId) internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(sender, nft, nftId));
    }

    function getTokenListingHash(address sender, uint256 nonce) internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(sender, nonce));
    }
    
}