import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { makeSwap, TOKEN_ABI } from "../scripts/utils";

const UST = "0xa47c8bf37f92aBed4A126BDA807A7b7498661acD";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

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

    const hash = await nftSwap.calculateNFTListingHash(signers[0].address, nft.address, 1);
    const hash2 = await nftSwap.calculateNFTListingHash(signers[0].address, nft.address, 2);
  
    await ethers.provider.send('evm_mine', []);
  
    await nftSwap.connect(signers[1]).submitNFTBuyOrder(hash, { value: ethers.utils.parseEther('100.0') });
    await nftSwap.connect(signers[2]).submitNFTBuyOrder(hash2, { value: ethers.utils.parseEther('10.0') });
  
    await ethers.provider.send('evm_mine', []);

    expect(await nft.balanceOf(signers[0].address)).to.equal(3);
    expect(await nft.balanceOf(signers[1].address)).to.equal(2);
    expect(await nft.balanceOf(signers[2].address)).to.equal(1);

    const order1 = await nftSwap.getOrder(hash);
    const order2 = await nftSwap.getOrder(hash2);

    expect(order1[5]).to.equal(signers[1].address);
    expect(order2[5]).to.equal(signers[2].address);

    await makeSwap(signers[0], [WETH,UST], '1.0');

    const tokenContract = new ethers.Contract(UST, TOKEN_ABI, ethers.provider);
    
    await tokenContract.connect(signers[0]).approve(nftSwap.address, '999999999999999999999999999');

    await ethers.provider.send('evm_mine', []);

    const tokenBalance = await tokenContract.balanceOf(signers[0].address);

    await nftSwap.createOTCSellOrder(2046818900, UST, tokenBalance.div(2), ethers.utils.parseEther('0.5'));
    await nftSwap.createOTCSellOrder(2046818900, UST, tokenBalance.div(2), ethers.utils.parseEther('0.5'));

    await ethers.provider.send('evm_mine', []);

    const tokenListings = await nftSwap.getAllTokenListings(signers[0].address);

    const preBalance = await ethers.provider.getBalance(signers[0].address);

    await nftSwap.connect(signers[2]).submitOTCBuyOrder(tokenListings[0], { value: ethers.utils.parseEther('0.5') });

    const postBalance = await ethers.provider.getBalance(signers[0].address);

    await ethers.provider.send('evm_mine', []);

    // Expect new balance to equal 0.5 ETH - contract fee
    expect(postBalance.sub(preBalance)).to.equal(BigNumber.from(ethers.utils.parseEther('0.5')).mul(95).div(100));
    
  });
});
