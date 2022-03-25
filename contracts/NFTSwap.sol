//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Orders.sol";
import "./libraries/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IERC1155.sol";

// solhint-disable not-rely-on-time, no-empty-blocks, avoid-low-level-calls
contract NFTSwap is Ownable {
    using SafeMath for uint256;

    uint256 private _exchangeInProgress; // 0 = not in progress; 1 = in progress
    uint256 private _feePercent = 500; // Extra 2 digits; 500 = 5%

    mapping(bytes32 => Orders.NFTListing) private _orders;
    mapping(bytes32 => Orders.TokenListing) private _otcOrders;
    mapping(address => uint256) private _totalOTCOrders;

    constructor() {}

    receive() external payable {}

    fallback() external payable {}

    /// <======= MODIFIERS =======> ///

    // Reentrancy prevention modifier
    modifier exchangeInProgress() {
        require(_exchangeInProgress == 0, "Exchange in progress");
        _exchangeInProgress = 1;
        _;
        _exchangeInProgress = 0;
    }

    /// <======= VIEW FUNCTIONS =======> ///

    /**
     * @dev Calculates the NFT listing hash
     *
     * @param lister the lister's address
     * @param nft the main nft address
     * @param nftId the individual NFT ID
     *
     * @return listingHash corresponding to the mapping key
     */
    function calculateNFTListingHash(
        address lister,
        address nft,
        uint256 nftId
    ) external view returns (bytes32) {
        bytes32 listingHash = Orders.getNFTListingHash(lister, nft, nftId);
        if (_orders[listingHash].nft == 0) {
            return keccak256(abi.encodePacked(uint256(0)));
        } else {
            return listingHash;
        }
    }

    /**
     * @dev Calculates ERC20 listing hash
     *
     * @param lister the lister's address
     * @param nonce the contract tx count for the lister
     *
     * @return listingHash corresponding to the mapping key
     */
    function calculateTokenListingHash(address lister, uint256 nonce)
        external
        view
        returns (bytes32)
    {
        bytes32 listingHash = Orders.getTokenListingHash(lister, nonce);
        if (_otcOrders[listingHash].lister == address(0)) {
            return keccak256(abi.encodePacked(uint256(0)));
        }

        return listingHash;
    }

    /**
     * @dev Get all ERC20 listing hashes from a lister
     *
     * @param lister the lister's address
     *
     * @return listings the list of all bytes32 listing hashes
     */
    function getAllTokenListings(address lister)
        external
        view
        returns (bytes32[] memory)
    {
        uint256 totalListings = _totalOTCOrders[lister];
        bytes32[] memory listings = new bytes32[](totalListings);

        if (totalListings == 0) return listings;

        for (uint256 i = 0; i < totalListings; ) {
            listings[i] = Orders.getTokenListingHash(lister, i + 1);
            unchecked {
                ++i;
            }
        }

        return listings;
    }

    /**
     * @dev Requests NFT order details from mapping
     *
     * @param listing the listing hash to lookup in mapping
     */
    function getNFTListing(bytes32 listing)
        external
        view
        returns (Orders.NFTListing memory)
    {
        return _orders[listing];
    }

    /**
     * @dev Requests ERC20 order details from mapping
     *
     * @param listing the listing hash to lookup in mapping
     */
    function getTokenListing(bytes32 listing)
        external
        view
        returns (Orders.TokenListing memory)
    {
        return _otcOrders[listing];
    }

    /**
     * @dev Function to take fee from order amount
     *
     * @param orderAmount the payment amount requested in sell order
     *
     * @return feeAmount the fee amount to subtract from order amount
     */
    function _takeFee(uint256 orderAmount) private view returns (uint256) {
        if (_feePercent > 0) {
            return orderAmount.mul(_feePercent).div(10000);
        } else {
            return 0;
        }
    }

    /// <======= MUTATIVE FUNCTIONS =======> ///

    /**
     * @dev Creates NFT sell order. Calls internal function immediately
     *
     * @param expiry the timestamp which the order expires
     * @param nft the main NFT contract address
     * @param nftId the individual NFT ID
     * @param paymentAmount output amount desired in ETH
     */
    function createNFTSellOrder(
        uint64 expiry,
        address nft,
        uint256 nftId,
        uint256 paymentAmount
    ) external {
        _createNFTSellOrder(msg.sender, expiry, nft, nftId, paymentAmount);
    }

    /**
     * @dev Sets open NFT sell order to cancelled
     *
     * @param listingId the listing ID from _orders mapping.
     */
    function cancelSellOrder(bytes32 listingId) external {
        require(_orders[listingId].lister == msg.sender, "Not lister");
        require(
            block.timestamp <= _orders[listingId].expiry,
            "Already expired"
        );
        require(_orders[listingId].status == 0, "Already inactive");

        _orders[listingId].status = 2;
    }

    /**
     * @dev Creates sell order for a fungible (ERC20) token
     *
     * @param expiry the timestamp which the order expires
     * @param token the token to sell
     * @param tokenAmount the amount of the token to sell
     * @param paymentAmount the expected output in ETH
     */
    function createOTCSellOrder(
        uint64 expiry,
        IERC20 token,
        uint256 tokenAmount,
        uint256 paymentAmount
    ) external {
        _createOTCSellOrder(
            msg.sender,
            expiry,
            token,
            tokenAmount,
            paymentAmount
        );
    }

    /**
     * @dev Creates sell order for a fungible (ERC20) token
     *
     * @param lister the listing address passed from msg.sender
     * @param expiry the timestamp which the order expires
     * @param token the token to sell
     * @param tokenAmount the amount of the token to sell
     * @param paymentAmount the expected output in ETH
     */
    function _createOTCSellOrder(
        address lister,
        uint64 expiry,
        IERC20 token,
        uint256 tokenAmount,
        uint256 paymentAmount
    ) private {
        require(
            token.balanceOf(lister) >= tokenAmount,
            "Not enough balance in wallet"
        );
        require(
            token.allowance(lister, address(this)) >= tokenAmount,
            "Not approved"
        );

        uint256 totalOrders = _totalOTCOrders[lister].add(1);
        _totalOTCOrders[lister] = totalOrders;

        bytes32 listHash = Orders.getTokenListingHash(lister, totalOrders);

        _otcOrders[listHash] = Orders.TokenListing({
            lister: lister,
            taker: address(0),
            token: uint160(address(token)),
            tokenAmount: tokenAmount,
            expiry: expiry,
            paymentAmount: paymentAmount,
            status: 0
        });

        emit OTCSellOrderCreated(lister, listHash);
    }

    /**
     * @dev Submit ERC20 Buy Order
     *
     * @param listingId the bytes32 listing hash
     */
    function submitOTCBuyOrder(bytes32 listingId)
        external
        payable
        exchangeInProgress
    {
        _submitOTCBuyOrder(listingId);
    }

    /**
     * @dev Private function to handle ERC20 buy order
     *
     * @param listingId the bytes32 listing hash
     */
    function _submitOTCBuyOrder(bytes32 listingId) private {
        uint256 preBalance = address(this).balance.sub(msg.value);

        Orders.TokenListing storage listing = _otcOrders[listingId];

        address lister = listing.lister;
        IERC20 token = IERC20(address(listing.token));
        uint256 paymentAmount = listing.paymentAmount;

        require(lister != address(0), "Listing not found");
        require(msg.value >= listing.paymentAmount, "Value too low");
        require(listing.status == 0, "Listing inactive");
        require(listing.expiry > block.timestamp, "Expired");

        require(_buy20(lister, token, paymentAmount), "Transfer failed");

        // Take fee
        uint256 feeToTake = _takeFee(paymentAmount);

        // Make ETH transfers
        (bool success, ) = lister.call{ value: paymentAmount.sub(feeToTake) }(
            ""
        );
        require(success, "Payment failed");

        // Update listing status
        listing.status = 1;
        listing.taker = msg.sender;

        uint256 postBalance = address(this).balance.sub(feeToTake);

        // If extra ETH was sent, refund to buyer
        if (postBalance.sub(preBalance) > 0) {
            (success, ) = msg.sender.call{ value: postBalance.sub(preBalance) }(
                ""
            );
            require(success, "Refund failed");
        }

        emit OTCSellOrderFilled(lister, msg.sender);
    }

    /**
     * @dev Submits a request to fill an NFT order
     *
     * @param listingId the list ID hash to look up the sell order
     */
    function submitNFTBuyOrder(bytes32 listingId)
        external
        payable
        exchangeInProgress
    {
        _submitNFTBuyOrder(listingId);
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
    function _createNFTSellOrder(
        address lister,
        uint64 expiry,
        address nft,
        uint256 nftId,
        uint256 paymentAmount
    ) private {
        // Perform validation checks
        require(expiry > block.timestamp, "Expired");
        require(
            IERC721(nft).ownerOf(nftId) == lister,
            "NFT not owned by sender"
        );

        // Calculate list hash ID
        bytes32 listHash = Orders.getNFTListingHash(lister, nft, nftId);

        // Save order
        _orders[listHash] = Orders.NFTListing({
            lister: lister,
            taker: address(0),
            expiry: expiry,
            nft: uint160(nft),
            nftId: nftId,
            paymentAmount: paymentAmount,
            status: 0,
            tokenType: 0
        });

        emit NFTSellOrderCreated(lister, listHash);
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
        Orders.NFTListing storage listing = _orders[listingId];

        address lister = listing.lister;
        address nft = address(listing.nft);
        uint256 paymentAmount = listing.paymentAmount;

        // General param check
        require(nft != address(0), "Listing not found");
        require(msg.value >= listing.paymentAmount, "Value too low");
        require(listing.status == 0, "Listing inactive");
        require(listing.expiry > block.timestamp, "Expired");

        if (listing.tokenType == 0) {
            require(
                _buy721(lister, IERC721(nft), listing.nftId),
                "Transfer failed"
            );
        } else {
            require(
                _buy1155(lister, IERC1155(nft), listing.nftId),
                "Transfer failed"
            );
        }

        // Take fee
        uint256 feeToTake = _takeFee(paymentAmount);

        // Make ETH transfers
        (bool success, ) = lister.call{ value: paymentAmount.sub(feeToTake) }(
            ""
        );
        require(success, "Payment failed");

        // Update listing status
        listing.status = 1;
        listing.taker = msg.sender;

        // Check balance after deposit and fee
        uint256 postBalance = address(this).balance.sub(feeToTake);

        // If extra ETH was sent, refund it to buyer
        if (postBalance.sub(preBalance) > 0) {
            (success, ) = msg.sender.call{ value: postBalance.sub(preBalance) }(
                ""
            );
            require(success, "Refund failed");
        }

        emit NFTSellOrderFilled(lister, msg.sender);
    }

    /**
     * @dev Core logic to check and transfer ERC20 asset
     *
     * @param lister the lister's address
     * @param token the erc20 token to transfer
     * @param tokenAmount the amount of the erc20 token to exchange
     *
     * @return bool indicates success
     */
    function _buy20(
        address lister,
        IERC20 token,
        uint256 tokenAmount
    ) private returns (bool) {
        require(
            token.allowance(lister, address(this)) >= tokenAmount,
            "Lister has not approved contract"
        );
        require(
            token.balanceOf(lister) >= tokenAmount,
            "Lister no longer has balance"
        );

        token.transferFrom(lister, msg.sender, tokenAmount);

        return true;
    }

    /**
     * @dev Core logic to check and transfer ERC721 asset
     *
     * @param lister address of seller account
     * @param nft NFT contract
     * @param nftId uint256 ID of individual NFT
     *
     * @return bool indicates success
     */
    function _buy721(
        address lister,
        IERC721 nft,
        uint256 nftId
    ) private returns (bool) {
        // Ensure NFT is approved and seller account owns it
        require(
            nft.getApproved(nftId) == address(this),
            "NFT owner must approve contract"
        );
        require(nft.ownerOf(nftId) == lister, "Lister no longer owns NFT");

        // Transfer NFT directly from current owner to buyer
        nft.safeTransferFrom(lister, msg.sender, nftId, "");

        return true;
    }

    /**
     * @dev Core logic to check and transfer ERC1155 asset
     *
     * @param lister address of seller account
     * @param nft address of NFT contract
     * @param nftId uint256 ID of individual NFT
     *
     * @return bool indicates success
     */
    function _buy1155(
        address lister,
        IERC1155 nft,
        uint256 nftId
    ) private returns (bool) {
        // Ensure NFT is approved and seller account owns it
        require(
            nft.isApprovedForAll(lister, address(this)),
            "NFT owner must approve contract"
        );
        require(nft.balanceOf(lister, nftId) > 0, "Lister no longer owns NFT");

        // Transfer NFT directly from current owner to buyer
        nft.safeTransferFrom(lister, msg.sender, nftId, 1, "");

        return true;
    }

    /// <======= EVENTS =======> ///

    event NFTSellOrderCreated(address indexed lister, bytes32 listingHash);
    event NFTSellOrderFilled(address indexed lister, address indexed taker);
    event NFTOrderCancelled(address indexed lister, bytes32 listingHash);
    event OTCSellOrderCreated(address indexed lister, bytes32 listingHash);
    event OTCSellOrderFilled(address indexed lister, address indexed taker);
    event OTCOrderCancelled(address indexed lister, bytes32 listingHash);
}
