const { LZ_ADDRESS } = require("@layerzerolabs/lz-sdk")

function getLayerZeroAddress(networkName) {
    console.log("LZ_ADDRESS:" + JSON.stringify(LZ_ADDRESS))
    if (networkName === "base-testnet") {
        LZ_ADDRESS[networkName] = "0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab"
    }
    if(!Object.keys(LZ_ADDRESS).includes(networkName)){
        throw new Error("Unknown networkName: " + networkName);
    }
    console.log(`networkName[${networkName}]`)
    // if (networkName === "goerli") {
    //     return "0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23"
    // }
    return LZ_ADDRESS[networkName];
}

module.exports = {
    getLayerZeroAddress
}