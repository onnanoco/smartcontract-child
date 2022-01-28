// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Library.sol";
import "./IMOEToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

// *** IMPORTANT ***
//
// BEFORE DEPLOY
// --------------
// erase _mint() line on initialize()
// change duration require() function on voteForAttack()
// change duration require() function on voteForDeffense()
// change duration require() function on unstake()
// change duration require() function on clearRound()
// change duration require() function on resolveAttack()
// change duration require() function on resolveDefense()

contract MOEToken is ContextUpgradeable, AccessControlEnumerableUpgradeable, IMOEToken, ERC20Upgradeable {

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE"); // Polygon mapping

    mapping(uint256 => Lib.Onnanoco) public onnanocos;
    mapping(uint256 => Lib.Round) public rounds;

    uint256 public totalRounds;
    uint256 public totalOnnanocos;

    mapping(uint256 => Lib.Vote[]) public defenseVotes;
    mapping(uint256 => Lib.Vote[]) public attackVotes;
    mapping(address => Lib.Stake[]) public stakes;

    // Add onnanoco data
    function addOnnanoco(string memory name, bytes32 hash, bytes2 hashFunction, uint8 hashSize, uint256 amount) public {
  
        _burn(_msgSender(), amount);

        // add onnanoco base data
        onnanocos[totalOnnanocos] = Lib.Onnanoco(name, _msgSender(), Lib.Multihash(hash, hashFunction, hashSize), Lib.Status.NORMAL, block.timestamp, 0, totalRounds);

        // setup round
        rounds[totalRounds] = Lib.Round(totalOnnanocos, amount, 0, 0, 1);

        // vote for defense
        Lib.Vote memory vote = Lib.Vote(totalOnnanocos, _msgSender(), amount, block.timestamp);
        defenseVotes[totalRounds].push(vote);

        // increase onnanoco index
        totalOnnanocos++;
        totalRounds++;
    }

    // Get minimum attack amount
    function getMinimumAttackAmount(uint256 id) public view returns (uint256 amount) {

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory round = rounds[roundId];

        uint256 minimumAmount = ((round.totalDefenseAmount + round.totalAttackAmount) * 2) - (round.totalAttackAmount * 3);

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

            onnanocos[id].status = Lib.Status.IN_DISPUTE;
            rounds[roundId].timestamp = block.timestamp;

        } else {
            
            Lib.Round memory round = rounds[roundId];

            uint256 duration = block.timestamp - round.timestamp;
            //require(duration < 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
            require(duration < 60 * 60, 'Dispute window is 1 hour'); // dev
        }

        attackVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));
        rounds[roundId].totalAttackAmount += amount;
        rounds[roundId].totalVotes++;
    }

    // Get minimum defense amount
    // id : id of the character
    function getMinimumDefenseAmount(uint256 id) public view returns (uint256 amount) {

        require(onnanocos[id].status == Lib.Status.IN_DISPUTE, 'Round is not in dispute');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory round = rounds[roundId];

        uint256 minimumAmount = ((round.totalDefenseAmount + round.totalAttackAmount) * 2) - (round.totalDefenseAmount * 3);

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

        uint256 minimumAmount = ((round.totalDefenseAmount + round.totalAttackAmount) * 2) - (round.totalDefenseAmount * 3);

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration < 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration < 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        require(amount >= minimumAmount, 'Less then MIN defense amount');
        
        _burn(_msgSender(), amount);
        defenseVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));

        rounds[roundId].totalDefenseAmount += amount;
        rounds[roundId].totalVotes++;
    }

    // clearRound
    // roundId : ID for the round
    function clearRound(uint256 roundId) public {

        Lib.Round memory round = rounds[roundId];
        Lib.Onnanoco storage onnanoco = onnanocos[round.onnanocoId];

        require(onnanoco.roundId == roundId, 'Invalid round id');

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is not over'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is not over'); // dev

        if (round.totalAttackAmount > round.totalDefenseAmount) { // Attackers win
            _mint(_msgSender(), round.totalAttackAmount / 100 * 2);
            onnanoco.status = Lib.Status.DEPRECATED;

        } else if(round.totalAttackAmount < round.totalDefenseAmount) { // Attackeres lose
            _mint(_msgSender(), round.totalDefenseAmount / 100 * 2);
            onnanoco.status = Lib.Status.NORMAL;

            // new round
            rounds[totalRounds] = Lib.Round(round.onnanocoId, 0, 0, 0, 1);
            onnanoco.roundId = totalRounds;

            // new vote
            Lib.Vote memory vote = defenseVotes[roundId][0];

            Lib.Vote memory newVote = Lib.Vote(round.onnanocoId, vote.voter, vote.amount, block.timestamp);
            defenseVotes[totalRounds].push(newVote);

            // increase roundId
            totalRounds++;
        }
        
    }

    function resolveAttack(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = attackVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = round.totalAttackAmount + round.totalDefenseAmount;

        if (round.totalAttackAmount > round.totalDefenseAmount) {
            
            _mint(_msgSender(), totalAmount * vote.amount / round.totalAttackAmount);

        }

        attackVotes[roundId][voteId].voter = address(0);

    }

    function resolveDefense(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = defenseVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = round.totalAttackAmount + round.totalDefenseAmount;

        if (round.totalAttackAmount < round.totalDefenseAmount) {

            if (voteId > 0) {

                _mint(_msgSender(), totalAmount * vote.amount / round.totalDefenseAmount);

            } else { // 1st defender

                _mint(_msgSender(), (totalAmount * vote.amount / round.totalDefenseAmount) - vote.amount);
            }

        }

        defenseVotes[roundId][voteId].voter = address(0);
    }
    
    function stake(uint256 id, uint256 amount) public {
    
        require(amount > 0, 'Cannot stake 0 MOE');
        require(onnanocos[id].status == Lib.Status.NORMAL, 'Round is not in normal status');

        _burn(_msgSender(), amount);

        stakes[_msgSender()].push(Lib.Stake(id, amount, block.timestamp));
        onnanocos[id].totalStakingAmount += amount;
    }
    
    function unstake(uint256 stakeId) public {

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];
        
        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'Round is in dispute status');
        
        uint256 duration = block.timestamp - stakeInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 50, 'Minimum duration is 50 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 hour'); // Test

        uint256 reward = stakeInfo.amount * duration / (60 * 60 * 24 * 50);

        if (onnanocos[stakeInfo.id].status == Lib.Status.DEPRECATED) {
            reward = 0;
        }

        _mint(_msgSender(), stakeInfo.amount + reward);
        onnanocos[stakeInfo.id].totalStakingAmount -= stakeInfo.amount;
    }

    function getStakeRewardAmount(uint256 stakeId) public view returns(uint256) {

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];

        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'Round is in dispute status');

        uint256 duration = block.timestamp - stakeInfo.timestamp;

        uint256 reward = stakeInfo.amount * duration / (60 * 60 * 24 * 100);

        if (onnanocos[stakeInfo.id].status == Lib.Status.DEPRECATED) {
            reward = 0;
        }

        return reward;
    }

    function receiveStakeReward(uint256 stakeId) public {

        uint256 reward = getStakeRewardAmount(stakeId);

        stakes[_msgSender()][stakeId].timestamp = block.timestamp;
        _mint(_msgSender(), reward);
    }

    function getOwnerRewardAmount(uint256 id) public view returns(uint256){

        Lib.Onnanoco memory onnanocoInfo = onnanocos[id];

        require(onnanocoInfo.status == Lib.Status.NORMAL, 'Round is not in normal status');

        Lib.Vote memory voteInfo = defenseVotes[onnanocoInfo.roundId][0];

        uint256 duration = block.timestamp - voteInfo.timestamp;

        uint256 reward = voteInfo.amount * duration / (60 * 60 * 24 * 50);

        if (onnanocoInfo.status == Lib.Status.DEPRECATED) {
            reward = 0;
        }

        return reward;
    }

    function receiveOwnerReward(uint256 id) public {
        
        require(defenseVotes[onnanocos[id].roundId][0].voter == _msgSender(), 'Permission denied');

        uint256 reward = getOwnerRewardAmount(id);

        _mint(_msgSender(), reward);
        defenseVotes[onnanocos[id].roundId][0].timestamp = block.timestamp;
    }

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

    // Initializer
    function initialize(string memory name, string memory symbol, address childchangeProxy) public virtual initializer {
        
        __ERC20_init(name, symbol);
        _setupRole(DEPOSITOR_ROLE, childchangeProxy);

        _mint(_msgSender(), 10 ** 18 * 100); // dev faucet
    }
}