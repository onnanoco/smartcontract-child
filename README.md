# MOE Polygon Child Token

- truffleを使用します。


## Packages

```bash
npm install --save-dev @maticnetwork/pos-portal
npm install --save-dev @openzeppelin/contracts
npm install --save-dev @truffle/hdwallet-provider
npm install --save-dev truffle-export-abi
npm install --save-dev truffle-plugin-verify
```

## truffle-config.js

```js

const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');
const mnemonic = fs.readFileSync(".secret").toString().trim();

module.exports = {

  networks: {
    mumbai: {
      provider: () => new HDWalletProvider(mnemonic, `MUMBAI_ENDPOINT`, 0, 2),
      network_id: 80001,
      gas: 20000000,
      gasPrice: 3000000000,
      confirmations: 2,
      timeoutBlocks: 300,
    },
    mainnet: {
      provider: () => new HDWalletProvider(mnemonic, `POLYGON_ENDPOINT`, 0, 2),
      network_id: 137,
      gas: 6000000,
      gasPrice: 50000000000,
      confirmations: 2,
      timeoutBlocks: 300,
    }
  },

  compilers: {
    solc: {
      version: "0.8.2",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }
  },

  plugins: ['truffle-plugin-verify'],

  api_keys: {
    etherscan: 'ETHERSCAN_API_KEY',
    polygonscan: 'POLYGON_API_KEY'
  }
};
```
