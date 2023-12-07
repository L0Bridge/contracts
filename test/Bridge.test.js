const { expect } = require("chai")
const { ethers } = require("hardhat")

describe("Bridge", function() {
    it("Deployment should assign the total supply of tokens to the owner", async function() {
        const [owner] = await ethers.getSigners();

        const lzAddress = await ethers.getContractFactory("LZEndpointMock");

        const lzAddressDeploy = await lzAddress.deploy();

        console.log("test")
        // const ownerBalance = await hardhatToken.balanceOf(owner.address);
        // expect(await hardhatToken.totalSupply()).to.equal(ownerBalance);
    });
});

// const { TYPE_SWAP_REMOTE, TYPE_ADD_LIQUIDITY, TYPE_REDEEM_LOCAL_CALL_BACK, TYPE_WITHDRAW_REMOTE, ZERO_ADDRESS } = require("./util/constants")
// const { callAsContract, getAddr, deployNew, encodeParams } = require("./util/helpers")
//
// console.log("before Bridge")
// describe("Bridge:", function () {
//     // before(async function () {
//     //     ;({ owner, alice, badUser1, fakeContract } = await getAddr(ethers))
//     //     chainId = 1
//     //     nonce = 1
//     //     defaultGasAmount = 123
//     //     transferAndCallPayload = "0x"
//     //     defaultCreditObj = { credits: 0, idealBalance: 0 }
//     //     defaulSwapObject = { amount: 0, eqFee: 0, eqReward: 0, lpFee: 0, protocolFee: 0, lkbRemove: 0 }
//     //     defaultLzTxObj = { dstGasForCall: 0, dstNativeAmount: 0, dstNativeAddr: "0x" }
//     // })
//     console.log("before beforeEach")
//     beforeEach(async function () {
//         console.log("in beforeEach")
//         lzAddress = await deployNew("LZEndpointMock", [10001])
//         lzAddressTarget = await deployNew("LZEndpointMock", [10102])
//
//         bridgeContract = await deployNew("Bridge", [lzAddress.address,10001,"0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"])
//         bridgeContractTarget = await deployNew("Bridge", [lzAddressTarget.address,10102,"0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"])
//     })
//     it("DeployAll", async function () {
//         console.log("in DeployAll")
//         await lzAddress.setDestLzEndpoint(bridgeContractTarget.address, lzAddressTarget.address)
//     })
// })