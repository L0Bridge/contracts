// helper function to get the LayerZero endpoint address required by Bridge
let { getLayerZeroAddress } = require("../utils/layerzero")
// import {ethers} from 'hardhat';

function getDependencies() {
    if (hre.network.name === "hardhat") {
        return ["LZEndpointMock", "Router"]
    }
    return ["Router"]
}

// deploy step 1: execute contract initial
// deploy step 2: fix data and execute data set

// // execute contract initial
// module.exports = async ({ ethers, getNamedAccounts, deployments }) => {
//     const { deploy } = deployments
//     const { deployer } = await getNamedAccounts()
//
//     let lzAddress
//     console.log(`Network: ${hre.network.name}`)
//     lzAddress = getLayerZeroAddress(hre.network.name)
//
//     let l0ChainId;
//     let l0ToChainId;
//     let weth;
//     let prayLuckToken
//     if (hre.network.name === "mumbai") {
//         l0ChainId = 10109
//         l0ToChainId = 10102
//         weth = "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"
//         prayLuckToken = "0xAe34D0C711967c501e86d5D1766b08c99cf275Ed"
//     } else if (hre.network.name === "bsc-testnet") {
//         l0ChainId = 10102
//         l0ToChainId = 10109
//         weth = "0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F"
//         prayLuckToken = "0xAe34D0C711967c501e86d5D1766b08c99cf275Ed"
//     }
//     // first deploy TokenFactory
//     const tokenFactoryContract = await deploy("TokenFactory", {
//         from: deployer,
//         args: [],
//         log: true,
//         skipIfAlreadyDeployed: true,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> tokenFactoryContract: ${tokenFactoryContract}`)
//
//     const tokenFactory = await ethers.getContract("TokenFactory");
//     // deploy Bridge.sol
//     const bridgeContract = await deploy("Bridge", {
//         from: deployer,
//         args: [lzAddress, tokenFactory.address, l0ChainId,weth],
//         log: true,
//         skipIfAlreadyDeployed: false,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> bridgeContract: ${bridgeContract}`)
//
//     const bridgeContractFrom = await ethers.getContract("Bridge");
//
//     console.log("start setSendVersion")
//     await bridgeContractFrom.setSendVersion(3);
//     console.log("start setReceiveVersion")
//     await bridgeContractFrom.setReceiveVersion(3);
//
//     console.log("start setGasAmount 0")
//     await bridgeContractFrom.setGasAmount(l0ToChainId, 0, 200000);
//     console.log("start setGasAmount 1")
//     await bridgeContractFrom.setGasAmount(l0ToChainId, 1, 200000);
//     console.log("start setGasAmount 2")
//     await bridgeContractFrom.setGasAmount(l0ToChainId, 2, 200000);
//
//     // registerTokenMap + registerBridgeFrom + registerBridgeTo + registerBridgeCPTo + setBridge + setGasAmount + setSendVersion + setReceiveVersion
//     console.log("start registerTokenMap")
//     await bridgeContractFrom.registerTokenMap(prayLuckToken, "CP_PrayLuck", "LP_PrxyLuck", 18)
//
//     console.log("start registerBridgeFrom")
//     await bridgeContractFrom.registerBridgeFrom(l0ToChainId, prayLuckToken, prayLuckToken)
//
//     console.log("start registerBridgeTo")
//     await bridgeContractFrom.registerBridgeTo(l0ToChainId, prayLuckToken, prayLuckToken)
// }

// execute data set
module.exports = async ({ ethers, getNamedAccounts, deployments }) => {
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    let lzAddress
    console.log(`Network: ${hre.network.name}`)
    lzAddress = getLayerZeroAddress(hre.network.name)

    let l0ChainId;
    let l0ToChainId;
    let weth;
    let prayLuckToken

    let cpTokenTo
    let bridgeAddress
    if (hre.network.name === "mumbai") {
        l0ChainId = 10109
        l0ToChainId = 10102
        weth = "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"
        prayLuckToken = "0xAe34D0C711967c501e86d5D1766b08c99cf275Ed"

        cpTokenTo = "0xB173cf2B9BAADaBC0f208b20e6348af61402cAad"
        bridgeAddress = "0x445217cF82A3Ecfa520c1Bb5197b81016aFdd7a8B1d2dDc1D8D0714d5507434DAf1B1C083d720F52"
    } else if (hre.network.name === "bsc-testnet") {
        l0ChainId = 10102
        l0ToChainId = 10109
        weth = "0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F"
        prayLuckToken = "0xAe34D0C711967c501e86d5D1766b08c99cf275Ed"

        cpTokenTo = "0x786425b62De099b728cC12e90fDc86E2454dA747"
        bridgeAddress = "0xB1d2dDc1D8D0714d5507434DAf1B1C083d720F52445217cF82A3Ecfa520c1Bb5197b81016aFdd7a8"
    }
    // first deploy TokenFactory
    const tokenFactoryContract = await deploy("TokenFactory", {
        from: deployer,
        args: [],
        log: true,
        skipIfAlreadyDeployed: true,
        waitConfirmations: 1,
    })
    console.log(`  -> tokenFactoryContract: ${tokenFactoryContract}`)

    const tokenFactory = await ethers.getContract("TokenFactory");

    // deploy Bridge.sol
    const bridgeContract = await deploy("Bridge", {
        from: deployer,
        args: [lzAddress, tokenFactory.address, l0ChainId,weth],
        log: true,
        skipIfAlreadyDeployed: true,
        waitConfirmations: 1,
    })
    console.log(`  -> bridgeContract: ${bridgeContract}`)

    const bridgeContractFrom = await ethers.getContract("Bridge");

    let cpTokenFrom = await bridgeContractFrom.cpTokenMap(prayLuckToken)
    console.log("start registerBridgeCPTo")
    await bridgeContractFrom.registerBridgeCPTo(l0ToChainId, cpTokenFrom, cpTokenTo)
    console.log("start setBridge")
    await bridgeContractFrom.setBridge(l0ToChainId, bridgeAddress)
}

// module.exports = async ({ ethers, getNamedAccounts, deployments }) => {
//     const { deploy } = deployments
//     const { deployer } = await getNamedAccounts()
//
//     let lzAddress
//     console.log(`Network: ${hre.network.name}`)
//     // lzAddress = getLayerZeroAddress(hre.network.name)
//     // mock
//     lzAddress = await deploy("LZEndpointMock", {
//         from: deployer,
//         args: [10001],
//         log: true,
//         skipIfAlreadyDeployed: false,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> LayerZeroEndpoint: ${lzAddress.address}`)
//
//     const lzAddressFrom = await ethers.getContract("LZEndpointMock");
//
//     // let router = await ethers.getContract("Router")
//
//     // deploy Bridge.sol
//     const bridgeContract = await deploy("Bridge", {
//         from: deployer,
//         // args: [lzAddress.address],
//         args: [lzAddress.address,10001,"0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"],
//         log: true,
//         skipIfAlreadyDeployed: false,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> bridgeContract: ${bridgeContract}`)
//
//     const bridgeContractFrom = await ethers.getContract("Bridge");
//
//     // mock
//     lzAddressTarget = await deploy("LZEndpointMock", {
//         from: deployer,
//         args: [10102],
//         log: true,
//         skipIfAlreadyDeployed: false,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> LayerZeroEndpointTarget: ${lzAddressTarget.address}`)
//     const lzAddressTo = await ethers.getContract("LZEndpointMock");
//
//     const bridgeContractTarget = await deploy("Bridge", {
//         from: deployer,
//         // args: [lzAddress.address],
//         args: [lzAddressTarget.address,10102,"0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"],
//         log: true,
//         skipIfAlreadyDeployed: false,
//         waitConfirmations: 1,
//     })
//     console.log(`  -> bridgeContractTarget: ${bridgeContractTarget.address}`)
//     const bridgeContractTo = await ethers.getContract("Bridge");
//
//
//     await lzAddressFrom.setDestLzEndpoint(bridgeContractTarget.address, lzAddressTarget.address)
//
//     await lzAddressTo.setDestLzEndpoint(bridgeContract.address, lzAddress.address)
//
//     // registerTokenMap + registerBridgeFrom + registerBridgeTo + registerBridgeCPTo + setBridge + setGasAmount + setSendVersion + setReceiveVersion
//     let prayLuckToken = "0xAe34D0C711967c501e86d5D1766b08c99cf275Ed"
//     await bridgeContractFrom.registerTokenMap(prayLuckToken, "CP_PrayLuck", "LP_PrxyLuck", 18)
//     await bridgeContractTo.registerTokenMap(prayLuckToken, "CP_T_PrayLuck", "LP_T_PrxyLuck", 18)
//
//     await bridgeContractFrom.registerBridgeFrom(10102, prayLuckToken, prayLuckToken)
//     await bridgeContractTo.registerBridgeFrom(10001, prayLuckToken, prayLuckToken)
//
//     await bridgeContractFrom.registerBridgeTo(10102, prayLuckToken, prayLuckToken)
//     await bridgeContractTo.registerBridgeTo(10001, prayLuckToken, prayLuckToken)
//
//     let cpTokenFrom = await bridgeContractFrom.cpTokenMap(prayLuckToken)
//     let cpTokenTo = await bridgeContractTo.cpTokenMap(prayLuckToken)
//
//     await bridgeContractFrom.registerBridgeCPTo(10102, cpTokenFrom, cpTokenTo)
//     await bridgeContractTo.registerBridgeCPTo(10001, cpTokenTo, cpTokenFrom)
//
//     await bridgeContractFrom.setBridge(10102, bridgeContractTarget.address)
//     await bridgeContractTo.setBridge(10001, bridgeContract.address)
//
// }

module.exports.tags = ["Bridge", "test"]
module.exports.dependencies = getDependencies()
