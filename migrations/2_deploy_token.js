const MOEToken = artifacts.require("./MOEToken.sol");

const { deployProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function(deployer) {
    //await deployProxy(MOEToken, ['MOE Token', 'MOE', '0xb5505a6d998549090530911180f38aC5130101c6'], { deployer, initializer: 'initialize' }); // for Mumbai testnet

    await deployProxy(MOEToken, ['MOE Token', 'MOE', '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa'], { deployer, initializer: 'initialize' }); // for mainnet
};