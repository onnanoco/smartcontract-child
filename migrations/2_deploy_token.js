const MOEToken = artifacts.require("./MOEToken.sol");

module.exports = function(deployer) {
    deployer.deploy(MOEToken,'MOE Token', 'MOE', '0xb5505a6d998549090530911180f38aC5130101c6');
};