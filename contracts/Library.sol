// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

library Lib {

    enum Status { NORMAL, IN_DISPUTE, DEPRECATED }

    struct Multihash {
        bytes32 hash;
        bytes2 hashFunction;
        uint8 size;
    }
    
    // [TODO] Optimize gas cost
    struct Onnanoco {
        string name;
        address owner;
        Multihash multihash;
        Status status;
        uint256 timestamp;
        uint256 totalStakingAmount;
        uint256 roundId;
    }

    struct Round {
        uint256 onnanocoId;
        uint256 totalDefenseAmount;
        uint256 totalAttackAmount;
        uint256 timestamp;
    }

    struct Vote {
        uint256 id;
        address voter;
        uint256 amount;
        uint256 timestamp;
    }

    struct Stake {
        uint256 id;
        uint256 amount;
        uint256 timestamp;
    }
    
}