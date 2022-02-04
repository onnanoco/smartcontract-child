
const HDWalletProvider = require('@truffle/hdwallet-provider');

const fs = require('fs');
const mnemonic = fs.readFileSync(".secret").toString().trim();
const infuraPolygonRPC = fs.readFileSync(".infura_polygon_rpc").toString().trim();
const infuraMumbaiRPC = fs.readFileSync(".infura_mumbai_rpc").toString().trim();
const polygonscanKey = fs.readFileSync(".polygonscan_key").toString().trim();

module.exports = {
 
  networks: {
    live: {
      provider: () => new HDWalletProvider(mnemonic, infuraPolygonRPC),
      network_id: 137,
      gas: 6000000,
      gasPrice: 50000000000, 
      confirmations: 2,
      timeoutBlocks: 300,
     // skipDryRun: true
    },
    mumbai: {
      provider: () => new HDWalletProvider(mnemonic, infuraMumbaiRPC),
      network_id: 80001,
      gas: 6000000,
      gasPrice: 4000000000,
      confirmations: 2,
      timeoutBlocks: 300,
     // skipDryRun: true
    },
  },

  mocha: {
    // timeout: 100000
  },

  plugins: ['truffle-plugin-verify']
  ,
  api_keys: {
    polygonscan: polygonscanKey,
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.2",
       settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
       }
    }
  },
};
