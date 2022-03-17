// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IPropertyValidator.sol";
import "../interfaces/IERC20.sol";

library Orders {

    enum SaleStatus {
        ACTIVE,
        FILLED,
        CANCELLED
    }

    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct NFTListing {
        address lister;
        address taker;
        uint256 expiry;
        address nft;
        uint256 nftId;
        uint256 paymentAmount;
        TokenType tokenType;
        SaleStatus status;
    }

    struct TokenListing {
        IERC20 token;
        uint256 tokenAmount;
        uint256 paymentAmount;
        uint256 expiry;
        address lister;
        address taker;
        SaleStatus status;
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