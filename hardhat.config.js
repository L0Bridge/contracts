/** @type import('hardhat/config').HardhatUserConfig */
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-solhint");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("hardhat-contract-sizer");
require("hardhat-tracer");
require("@primitivefi/hardhat-dodoc");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-spdx-license-identifier");

function accounts(chainKey) {
    return { mnemonic: "test test test test test test test test test test test junk" }
}

module.exports = {
    namedAccounts: {
        deployer: 0,
    },

    // defaultNetwork: "hardhat",
    defaultNetwork: "base-testnet",

    networks: {
        // mainnet: {
        //     url: "http://192.168.0.131",
        //     zksync: false,
        // },
        avalanche: {
            url: "https://api.avax.network/ext/bc/C/rpc",
            chainId: 43114,
        },
        'bsc-testnet': {
            // url: 'https://bsc-testnet.public.blastapi.io',
            // url: 'https://data-seed-prebsc-1-s1.binance.org:8545/',
            url: 'https://data-seed-prebsc-2-s1.bnbchain.org:8545',
            // url: 'https://bsc-testnet.publicnode.com',
            chainId: 97,
            gasPrice: 10000000000,
            gas: 8000000,
            accounts: accounts(),
        },
        mumbai: {
            url: "https://rpc-mumbai.maticvigil.com/",
            // url: "https://polygon-mumbai-pokt.nodies.app",
            // url: "https://polygon-mumbai-bor.publicnode.com",
            chainId: 80001,
            gasPrice: 10000000000,
            // gas: 1000000,
            accounts: accounts(),
        },
        'arbitrum-rinkeby': {
            url: `https://rinkeby.arbitrum.io/rpc`,
            chainId: 421611,
            accounts: accounts(),
        },
        'optimism-kovan': {
            url: `https://kovan.optimism.io/`,
            chainId: 69,
            accounts: accounts(),
        },
        'fantom-testnet': {
            url: `https://rpc.testnet.fantom.network/`,
            chainId: 4002,
            accounts: accounts(),
        },
        'base-testnet': {
            url: `https://base-goerli.public.blastapi.io`,
            // url: `https://api-goerli.basescan.org/api`,
            chainId: 84531,
            accounts: accounts(),
        },
        lineaTestnet: {
            url: `https://rpc.goerli.linea.build/`,
        },
    },
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    contractSizer: {
        alphaSort: false,
        runOnCompile: true,
        disambiguatePaths: false,
    },
    etherscan: {
        // ploygon
        apiKey: "",
    },
};
