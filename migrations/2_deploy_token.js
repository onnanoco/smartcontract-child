const MOEToken = artifacts.require("./MOEToken.sol");

const { deployProxy } = require("@openzeppelin/truffle-upgrades");

/*
module.exports = async function(deployer) {

    deployer.deploy(MOEToken, 'MOE Token', 'MOE', '');
}
*/

module.exports = async function(deployer) {
    await deployProxy(MOEToken, ['MOE Token', 'MOE', '18', '0xb5505a6d998549090530911180f38aC5130101c6'], { deployer, initializer: 'initialize' });
};