// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.6.0;

import "./Library.sol";
import "@maticnetwork/pos-portal/contracts/child/ChildToken/UpgradeableChildERC20/UChildERC20.sol";
//import "@maticnetwork/pos-portal/contracts/child/ChildToken/UpgradeableChildERC20/UChildERC20Proxy.sol";

// *** IMPORTANT ***
//
// BEFORE DEPLOY
// --------------
// erase _mint() line on constructor function
// change duration require() function on voteForAttack()
// change duration require() function on voteForDeffense()
// change duration require() function on unstake()
// change duration require() function on clearRound()
// change duration require() function on resolveAttack()
// change duration require() function on resolveDefense()
//
contract MOEToken is UChildERC20 {

    //string public constant NAME = "MOE Token";
    //string public constant SYMBOL = "MOE";
    //uint8 public constant DECIMALS = 18;

    mapping(uint256 => Lib.Onnanoco) public onnanocos;
    mapping(uint256 => Lib.Round) public rounds;

    uint256 public totalRounds;
    uint256 public totalOnnanocos;

    mapping(uint256 => Lib.Vote[]) public defenseVotes;
    mapping(uint256 => Lib.Vote[]) public attackVotes;

    mapping(address => Lib.Stake[]) public stakes;

    //bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE"); // Polygon mapping

    function addOnnanoco(string memory name, bytes32 hash, bytes2 hashFunction, uint8 hashSize, uint256 amount) public {
  
        _burn(_msgSender(), amount);

        // add onnanoco base data
        onnanocos[totalOnnanocos] = Lib.Onnanoco(name, _msgSender(), Lib.Multihash(hash, hashFunction, hashSize), Lib.Status.NORMAL, block.timestamp, 0, totalRounds);

        // setup round
        rounds[totalRounds] = Lib.Round(totalOnnanocos, amount, 0, 0);

        // vote for defense
        Lib.Vote memory vote = Lib.Vote(totalOnnanocos, _msgSender(), amount, block.timestamp);
        defenseVotes[totalRounds].push(vote);

        // increase onnanoco index
        totalOnnanocos.add(1);
        totalRounds.add(1);
    }

    // Get minimum attack amount
    // id : id of the character
    function getMinimumAttackAmount(uint256 id) public view returns (uint256 amount) {

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory round = rounds[roundId];

        uint256 minimumAmount = (round.totalDefenseAmount.add(round.totalAttackAmount).mul(2)).sub(round.totalAttackAmount.mul(3));

        return minimumAmount;
    }

    // Vote for attack
    // id: id of the character
    // amount: defense amount
    function voteForAttack(uint256 id, uint256 amount) public {

        require(amount > 0, 'Cannot vote with 0 MOE');
        require(onnanocos[id].status != Lib.Status.DEPRECATED, 'Deprecated');
        
        uint256 minimumAmount = getMinimumAttackAmount(id);

        require(amount >= minimumAmount, 'Less then MIN attack amount');

        _burn(_msgSender(), amount);

        uint256 roundId = onnanocos[id].roundId;

        // 1st attack
        if (onnanocos[id].status == Lib.Status.NORMAL) {

            Lib.Round memory round = rounds[roundId];

            uint256 duration = block.timestamp.sub(round.timestamp);
            //require(duration < 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
            require(duration < 60 * 60, 'Dispute window is 1 hour'); // dev

            onnanocos[id].status = Lib.Status.IN_DISPUTE;
        } else {
            rounds[roundId].timestamp = block.timestamp;
        }

        attackVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));
        rounds[roundId].totalAttackAmount.add(amount);
    }

    // Get minimum defense amount
    // id : id of the character
    function getMinimumDefenseAmount(uint256 id) public view returns (uint256 amount) {

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory round = rounds[roundId];

        uint256 minimumAmount = ((round.totalDefenseAmount.add(round.totalAttackAmount)).mul(2)).sub(round.totalDefenseAmount.mul(3));

        return minimumAmount;
    }

    // Vote for defense
    // id: id of the character
    // amount: defense amount
    function voteForDefense(uint256 id, uint256 amount) public {

        require(amount > 0, 'Cannot vote with 0 MOE');
        require(onnanocos[id].status == Lib.Status.IN_DISPUTE, 'Round is not in dispute');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory round = rounds[roundId];

        uint256 minimumAmount = ((round.totalDefenseAmount.add(round.totalAttackAmount)).mul(2)).sub(round.totalDefenseAmount.mul(3));

        uint256 duration = block.timestamp.sub(round.timestamp);

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        require(amount >= minimumAmount, 'Less then MIN defense amount');
        
        _burn(_msgSender(), amount);
        defenseVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));

        rounds[roundId].totalDefenseAmount.add(amount);
    }

    // clearRound
    // roundId : ID for the round
    function clearRound(uint256 roundId) public {

        Lib.Round memory round = rounds[roundId];
        Lib.Onnanoco storage onnanoco = onnanocos[round.onnanocoId];

        require(onnanoco.roundId == roundId, 'Invalid round id');

        uint256 duration = block.timestamp.sub(round.timestamp);

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is not over'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is not over'); // dev

        if (round.totalAttackAmount > round.totalDefenseAmount) { // Attackers win
            _mint(_msgSender(), round.totalAttackAmount.div(50));
            onnanoco.status = Lib.Status.DEPRECATED;

        } else if(round.totalAttackAmount < round.totalDefenseAmount) { // Attackeres lose
            _mint(_msgSender(), round.totalDefenseAmount.div(50));
            onnanoco.status = Lib.Status.NORMAL;

            // new round
            rounds[totalRounds] = Lib.Round(round.onnanocoId, 0, 0, 0);

            Lib.Vote memory vote = defenseVotes[roundId][0];

            Lib.Vote memory newVote = Lib.Vote(round.onnanocoId, vote.voter, vote.amount, block.timestamp);
            defenseVotes[totalRounds].push(newVote);

            totalRounds.add(1);
        }
        
    }

    function resolveAttack(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = attackVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp.sub(round.timestamp);

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = round.totalAttackAmount.add(round.totalDefenseAmount);

        if (round.totalAttackAmount > round.totalDefenseAmount) {
            _mint(_msgSender(), totalAmount.mul(vote.amount).div(round.totalAttackAmount));
            attackVotes[roundId][voteId].voter = address(0);

        } else {
            attackVotes[roundId][voteId].voter = address(0);
        }

    }

    function resolveDefense(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = defenseVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp.sub(round.timestamp);

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = round.totalAttackAmount.add(round.totalDefenseAmount);

        if (round.totalAttackAmount < round.totalDefenseAmount && voteId > 0) {

            _mint(_msgSender(), totalAmount.mul(vote.amount).div(round.totalDefenseAmount));
            defenseVotes[roundId][voteId].voter = address(0);

        } else {
            defenseVotes[roundId][voteId].voter = address(0);
        }
    }
    
    // Stake MOE
    function stake(uint256 id, uint256 amount) public {
    
        require(amount > 0, 'Cannot stake 0 MOE');
        require(onnanocos[id].status == Lib.Status.NORMAL, 'Round is not in normal status');

        _burn(_msgSender(), amount);

        stakes[_msgSender()].push(Lib.Stake(id, amount, block.timestamp));
        onnanocos[id].totalStakingAmount.add(amount);
    }
    
    // Unstake MOE
    function unstake(uint256 stakeId) public {

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];
        
        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'Round is in dispute status');
        
        uint256 duration = block.timestamp - stakeInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 100, 'Minimum duration is 100 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 hour'); // Test

        uint256 bonus = stakeInfo.amount.mul(duration).div(60 * 60 * 24 * 100 * 20);

        if (onnanocos[stakeInfo.id].status == Lib.Status.DEPRECATED) {
            bonus = 0;
        }

        _mint(_msgSender(), stakeInfo.amount.add(bonus));
        onnanocos[stakeInfo.id].totalStakingAmount.sub(stakeInfo.amount);
    }

    // Test faucet
    function mintToken(uint256 amount) public {
        _mint(_msgSender(), amount);
    }
}