//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Orders.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IERC1155.sol";

/**
 * TODO:
 * Test ERC1155 listings and sales
 * Test ERC20 listings and sales
 * Gas optimizations where possible
 * Ancillary functions to support front-end (if needed)
*/

// solhint-disable not-rely-on-time, no-empty-blocks
contract NFTSwap {
    using SafeMath for uint256;

    uint256 private _exchangeInProgress; // 0 = not in progress; 1 = in progress
    uint256 private _feePercent = 500; // Extra 2 digits; 500 = 5%
    
    mapping (bytes32 => Orders.NFTListing) private _orders;
    mapping (bytes32 => Orders.TokenListing) private _otcOrders;
    mapping (address => uint256) private _totalOTCOrders;

    constructor() {}
    receive() external payable {}
    fallback() external payable {}

    // Reentrancy prevention modifier
    modifier exchangeInProgress {
        require(_exchangeInProgress == 0, "Exchange in progress");
        _exchangeInProgress = 1;
        _;
        _exchangeInProgress = 0;
    }

    /**
     * @dev Calculates the listing hash based on parameters
     *
     * @param lister the lister's address
     * @param nft the main nft address
     * @param nftId the individual NFT ID
     *
     * @return listingHash corresponding to the mapping key
     */
    function calculateListingHash(address lister, address nft, uint256 nftId) external view returns (bytes32)
    {
        bytes32 listingHash = Orders.getNFTListingHash(lister, nft, nftId);
        if (_orders[listingHash].nft == address(0)) {
            return keccak256(abi.encodePacked(uint256(0)));
        } else {
            return listingHash;
        }
    }

    /**
     * @dev Creates NFT sell order. Calls internal function immediately
     *
     * @param expiry the timestamp which the order expires
     * @param nft the main NFT contract address
     * @param nftId the individual NFT ID
     * @param paymentAmount output amount desired in ETH
     */
    function createNFTSellOrder(uint256 expiry, address nft, uint256 nftId, uint256 paymentAmount) external
    {
        _createNFTSellOrder(msg.sender, expiry, nft, nftId, paymentAmount);
    }

    /**
     * @dev Sets open NFT sell order to cancelled
     *
     * @param listingId the listing ID from _orders mapping.
     */
    function cancelSellOrder(bytes32 listingId) external
    {
        require(_orders[listingId].lister == msg.sender, "Not lister");
        require(block.timestamp <= _orders[listingId].expiry, "Already expired");
        require(_orders[listingId].status == Orders.SaleStatus.ACTIVE, "Already inactive");

        _orders[listingId].status = Orders.SaleStatus.CANCELLED;
    }

    /**
     * @dev Creates sell order for a fungible (ERC20) token
     *
     * @param expiry the timestamp which the order expires
     * @param token the token to sell
     * @param tokenAmount the amount of the token to sell
     * @param paymentAmount the expected output in ETH
     */
    function createOTCSellOrder(uint256 expiry, IERC20 token, uint256 tokenAmount, uint256 paymentAmount) external
    {
        require(token.balanceOf(msg.sender) >= tokenAmount, "Not enough balance in wallet");
        require(token.allowance(msg.sender, address(this)) >= tokenAmount, "Not approved");

        uint totalOrders = _totalOTCOrders[msg.sender].add(1);
        _totalOTCOrders[msg.sender] = totalOrders;

        bytes32 listingId = Orders.getTokenListingHash(msg.sender, totalOrders);

        _otcOrders[listingId] = Orders.TokenListing({
            lister: msg.sender,
            taker: address(0),
            token: token,
            tokenAmount: tokenAmount,
            expiry: expiry,
            paymentAmount: paymentAmount,
            status: Orders.SaleStatus.ACTIVE
        });
    }

    /**
     * @dev Submits a request to fill an NFT order
     *
     * @param listingId the list ID hash to look up the sell order
     */
    function submitNFTBuyOrder(bytes32 listingId) external payable exchangeInProgress()
    {
        _submitNFTBuyOrder(listingId);
    }

    /**
     * @dev Requests order details from mapping
     *
     * @param order the order hash to lookup in mapping
     */
    function getOrder(bytes32 order) external view returns (Orders.NFTListing memory)
    {
        return _orders[order];
    }

    /**
     * @dev Function to take fee from order amount
     *
     * @param orderAmount the payment amount requested in sell order
     *
     * @return feeAmount the fee amount to subtract from order amount
     */
    function _takeFee(uint256 orderAmount) private view returns (uint256)
    {
        if (_feePercent > 0) {
           return orderAmount.mul(_feePercent).div(10000); 
        } else {
            return 0;
        }
    }

    /**
     * @dev Creates NFT sell order. Calls internal function immediately
     *
     * @param lister passes in msg.sender from external function
     * @param expiry the timestamp which the order expires
     * @param nft the main NFT contract address
     * @param nftId the individual NFT ID
     * @param paymentAmount output amount desired in ETH
     */
    function _createNFTSellOrder(address lister, uint256 expiry, address nft, uint256 nftId, uint256 paymentAmount) private
    {
        // Perform validation checks
        require(expiry > block.timestamp, "Expired");
        require(IERC721(nft).ownerOf(nftId) == lister, "NFT not owned by sender");

        // Calculate list hash ID
        bytes32 listHash = Orders.getNFTListingHash(lister, nft, nftId);

        // Save order
        _orders[listHash] = Orders.NFTListing({
            lister: lister,
            taker: address(0),
            expiry: expiry,
            nft: nft,
            nftId: nftId,
            paymentAmount: paymentAmount,
            status: Orders.SaleStatus.ACTIVE,
            tokenType: Orders.TokenType.ERC721
        });
    }

    /**
     * @dev Submits a request to fill an NFT order
     *
     * @param listingId the list ID hash to look up the sell order
     */
    function _submitNFTBuyOrder(bytes32 listingId) private {
        // Get balance of contract prior to deposit
        uint256 preBalance = address(this).balance.sub(msg.value);

        // Get listing from storage
        Orders.NFTListing memory listing = _orders[listingId];

        // General param check
        require(listing.nft != address(0), "Listing not found");
        require(msg.value >= listing.paymentAmount, "Value too low");
        require(listing.status == Orders.SaleStatus.ACTIVE, "Listing inactive");
        require(listing.expiry > block.timestamp, "Expired");

        if (listing.tokenType == Orders.TokenType.ERC721) {
            _buy721(listing.lister, listing.nft, listing.nftId);
        } else {
            _buy1155(listing.lister, listing.nft, listing.nftId);
        }

        // Make ETH transfers
        (bool success, ) = listing.lister.call{value: listing.paymentAmount}("");
        require(success, "Payment failed");

        // Update listing status
        listing.status = Orders.SaleStatus.FILLED;
        listing.taker = msg.sender;

        // Take fee
        uint256 feeToTake = _takeFee(listing.paymentAmount);
        
        // Check balance after deposit
        uint256 postBalance = address(this).balance.sub(feeToTake);

        // If extra ETH was sent, refund it to buyer
        if (postBalance.sub(preBalance) > 0) {
            (success, ) = msg.sender.call{value: postBalance.sub(preBalance)}("");
            require(success, "Refund failed");         
        }
    }

    /**
     * @dev Core logic to check and transfer ERC721 asset
     *
     * @param lister address of seller account
     * @param nftAddr address of NFT contract
     * @param nftId uint256 ID of individual NFT
     */
    function _buy721(address lister, address nftAddr, uint256 nftId) private {
        // Initiate ERC721
        IERC721 nft = IERC721(nftAddr);

        // Ensure NFT is approved and seller account owns it
        require(nft.getApproved(nftId) == address(this), "NFT owner must approve contract");
        require(nft.ownerOf(nftId) == lister, "Lister no longer owns NFT");

        // Transfer NFT directly from current owner to buyer
        nft.safeTransferFrom(lister, msg.sender, nftId, "");
    }

    /**
     * @dev Core logic to check and transfer ERC1155 asset
     *
     * @param lister address of seller account
     * @param nftAddr address of NFT contract
     * @param nftId uint256 ID of individual NFT
     */
    function _buy1155(address lister, address nftAddr, uint256 nftId) private {
        // Initiate ERC115
        IERC1155 nft = IERC1155(nftAddr);

        // Ensure NFT is approved and seller account owns it
        require(nft.isApprovedForAll(lister, address(this)), "NFT owner must approve contract");
        require(nft.balanceOf(lister, nftId) > 0, "Lister no longer owns NFT");

        // Transfer NFT directly from current owner to buyer
        nft.safeTransferFrom(lister, msg.sender, nftId, 1, "");
    }
    
}
