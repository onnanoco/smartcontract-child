# MOEスマートコントラクト v.1.0.0 (Polygon Child Token)

- truffleを使用します。

## Packages

```bash
npm install
npx truffle deploy --network {NETWORK}
```

## Upgrade

### add contracts/MOETokenV2.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Library.sol";
import "./IMOEToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract MOETokenV2 is ContextUpgradeable, AccessControlEnumerableUpgradeable, IMOEToken, ERC20Upgradeable {

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE"); // Polygon mapping

    mapping(uint256 => Lib.Onnanoco) public onnanocos;
    mapping(uint256 => Lib.Round) public rounds;

    uint256 public totalRounds;
    uint256 public totalOnnanocos;

    mapping(uint256 => Lib.Vote[]) public defenseVotes;
    mapping(uint256 => Lib.Vote[]) public attackVotes;
    mapping(address => Lib.Stake[]) public stakes;

    // Upgrade functions

    // Polygon mapping : deposit
    function deposit(address user, bytes calldata depositData) external override {
        require(hasRole(DEPOSITOR_ROLE, _msgSender()), "You're not allowed to deposit");
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    // Polygon mapping : withdraw
    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}
```

### add migrations/3_upgrade_token_v2.js

```js
const MOEToken = artifacts.require('MOEToken');
const MOETokenV2 = artifacts.require('MOETokenV2');


const { upgradeProxy } = require('@openzeppelin/truffle-upgrades');

module.exports = async function (deployer) {

    const existing = await MOEToken.deployed();
    const proxy = await upgradeProxy(existing.address, MOETokenV2);
};
```

### upgrade

```bash
npx truffle migrate --network {NETWORK}
```

## Testnet

- Contract address: 0x5ea8EE79368116FE841eb57c678b583CCF4F5141