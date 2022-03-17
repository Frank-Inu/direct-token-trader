import { expect } from "chai";
import { ethers } from "hardhat";

describe("NFTSwap", function () {
  it("Should create NFTs, list for sale, and fulfill order", async function () {
    const signers = await ethers.getSigners();

    // We get the contract to deploy
    const NFTSwap = await ethers.getContractFactory("NFTSwap");
    const nftSwap = await NFTSwap.deploy();
  
    await nftSwap.deployed();
  
    console.log("NFTSwap deployed to:", nftSwap.address);
    
    const NFT = await ethers.getContractFactory("ERC721");
    const nft = await NFT.deploy();
  
    await nft.deployed();
  
    await nft.mint();
    await nft.mint();
    await nft.mint();
    await nft.mint();
    await nft.mint();
    await nft.connect(signers[1]).mint();
  
    expect(await nft.ownerOf(1)).to.equal(signers[0].address);

    await ethers.provider.send('evm_mine', []);
  
    await nft.approve(nftSwap.address, 1);
    await nft.approve(nftSwap.address, 2);
    await nft.approve(nftSwap.address, 3);
    await nft.approve(nftSwap.address, 4);
    await nft.approve(nftSwap.address, 5);

    await ethers.provider.send('evm_mine', []);
  
    expect(await nft.balanceOf(signers[0].address)).to.equal(5);
  
    // expect(await nftSwap.totalOrders()).to.equal(5);

    await nftSwap.createNFTSellOrder(2046818900, nft.address, 1, ethers.utils.parseEther('10.0'));
    await nftSwap.createNFTSellOrder(2046818900, nft.address, 2, ethers.utils.parseEther('10.0'));
    await nftSwap.createNFTSellOrder(2046818900, nft.address, 3, ethers.utils.parseEther('10.0'));
    await nftSwap.createNFTSellOrder(2046818900, nft.address, 4, ethers.utils.parseEther('10.0'));
    await nftSwap.createNFTSellOrder(2046818900, nft.address, 5, ethers.utils.parseEther('10.0'));

    const hash = await nftSwap.calculateListingHash(signers[0].address, nft.address, 1);
  
    await ethers.provider.send('evm_mine', []);
  
    await nftSwap.connect(signers[1]).submitNFTBuyOrder(hash, { value: ethers.utils.parseEther('100.0')});
  
    await ethers.provider.send('evm_mine', []);

    console.log(`Address 0 NFT balance: ${await nft.balanceOf(signers[0].address)}`);
    console.log(`Address 1 NFT balance: ${await nft.balanceOf(signers[1].address)}`);
    console.log(`Address 0 ETH balance: ${await ethers.provider.getBalance(signers[0].address)}`);
    console.log(`Address 1 ETH balance: ${await ethers.provider.getBalance(signers[1].address)}`);

    expect(await nft.balanceOf(signers[0].address)).to.equal(4);
    expect(await nft.balanceOf(signers[1].address)).to.equal(2);
  });
});
