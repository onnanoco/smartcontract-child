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

        onnanocos[totalOnnanocos] = Lib.Onnanoco(name, _msgSender(), Lib.Multihash(hash, hashFunction, hashSize), Lib.Status.NORMAL, block.timestamp, 0, totalRounds);

        rounds[totalRounds] = Lib.Round(totalOnnanocos, amount, 0, 0, 1);

        Lib.Vote memory vote = Lib.Vote(totalOnnanocos, _msgSender(), amount, block.timestamp);
        defenseVotes[totalRounds].push(vote);

        totalOnnanocos++;
        totalRounds++;
    }

    function getMinimumAttackAmount(uint256 id) public view returns (uint256 amount) {

        if (id >= totalOnnanocos) {
            return 0;
        }

        if (onnanocos[id].status == Lib.Status.DEPRECATED) {
            return 0;
        }

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];

        if (((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) > (roundInfo.totalAttackAmount * 3)) {
            return ((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) - (roundInfo.totalAttackAmount * 3);
        } else {
            return 0;
        }
    }

    function voteForAttack(uint256 id, uint256 amount) public {

        require(id < totalOnnanocos, 'Invalid id');
        require(amount > 0, 'Cannot vote with 0 MOE');
        require(onnanocos[id].status != Lib.Status.DEPRECATED, 'Deprecated');
        
        uint256 minimumAmount = getMinimumAttackAmount(id);
        require(amount >= minimumAmount, 'Less than MIN attack amount');

        uint256 roundId = onnanocos[id].roundId;

        // 1st attack
        if (onnanocos[id].status == Lib.Status.NORMAL) {

            onnanocos[id].status = Lib.Status.IN_DISPUTE;
            rounds[roundId].timestamp = block.timestamp;

        } else {
            
            Lib.Round memory roundInfo = rounds[roundId];
            require(roundInfo.timestamp > 0, 'Round is empty');

            uint256 duration = block.timestamp - roundInfo.timestamp;
            //require(duration < 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
            require(duration < 60 * 60, 'Dispute window is 1 hour'); // dev
        }

        _burn(_msgSender(), amount);
        attackVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));

        rounds[roundId].totalAttackAmount += amount;
        rounds[roundId].totalVotes++;
    }

    function getMinimumDefenseAmount(uint256 id) public view returns (uint256 amount) {

        if (id >= totalOnnanocos) {
            return 0;
        }

        if (onnanocos[id].status != Lib.Status.IN_DISPUTE) {
            return 0;
        }

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];

        if (((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) > (roundInfo.totalDefenseAmount * 3)) {
            return ((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) - (roundInfo.totalDefenseAmount * 3);
        } else {
            return 0;
        }
    }

    function voteForDefense(uint256 id, uint256 amount) public {

        require(id < totalOnnanocos, 'Invalid id');
        require(amount > 0, 'Cannot vote with 0');
        require(onnanocos[id].status == Lib.Status.IN_DISPUTE, 'Round is not in dispute');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];
        require(roundInfo.timestamp > 0, 'Round is empty');

        uint256 minimumAmount = getMinimumDefenseAmount(id);
        require(amount >= minimumAmount, 'Less than MIN defense amount');

        uint256 duration = block.timestamp - roundInfo.timestamp;
        //require(duration < 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration < 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        _burn(_msgSender(), amount);
        defenseVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));

        rounds[roundId].totalDefenseAmount += amount;
        rounds[roundId].totalVotes++;
    }

    function clearRound(uint256 roundId) public {

        Lib.Round memory roundInfo = rounds[roundId];
        require(roundInfo.timestamp > 0, 'Invalid roundId');

        Lib.Onnanoco storage onnanoco = onnanocos[roundInfo.onnanocoId];
        require(onnanoco.roundId == roundId, 'Invalid roundId');

        uint256 duration = block.timestamp - roundInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is not over'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is not over'); // dev

        if (roundInfo.totalAttackAmount > roundInfo.totalDefenseAmount) { // Attackers win
            _mint(_msgSender(), roundInfo.totalAttackAmount / 100 * 1);
            onnanoco.status = Lib.Status.DEPRECATED;

        } else if(roundInfo.totalAttackAmount < roundInfo.totalDefenseAmount) { // Attackers lose
            _mint(_msgSender(), roundInfo.totalDefenseAmount / 100 * 1);
            onnanoco.status = Lib.Status.NORMAL;

            // new round
            rounds[totalRounds] = Lib.Round(roundInfo.onnanocoId, 0, 0, 0, 1);
            onnanoco.roundId = totalRounds;

            // new vote
            Lib.Vote memory vote = defenseVotes[roundId][0];

            Lib.Vote memory newVote = Lib.Vote(roundInfo.onnanocoId, vote.voter, vote.amount, block.timestamp);
            defenseVotes[totalRounds].push(newVote);

            // increase roundId
            totalRounds++;
        }
        
    }

    function resolveAttack(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory voteInfo = attackVotes[roundId][voteId];
        require(voteInfo.timestamp > 0, 'Invalid voteId');
        require(_msgSender() == voteInfo.voter, 'Access denied');

        Lib.Round memory roundInfo = rounds[roundId];
        require(roundInfo.timestamp > 0, 'Invalid roundId');
        
        uint256 duration = block.timestamp - roundInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = roundInfo.totalAttackAmount + roundInfo.totalDefenseAmount;

        if (roundInfo.totalAttackAmount > roundInfo.totalDefenseAmount) {
            _mint(_msgSender(), totalAmount * voteInfo.amount / roundInfo.totalAttackAmount);
        }

        attackVotes[roundId][voteId].voter = address(0);
    }

    function resolveDefense(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory voteInfo = defenseVotes[roundId][voteId];
        require(voteInfo.timestamp > 0, 'Invalid voteId');
        require(_msgSender() == voteInfo.voter, 'Access denied');

        Lib.Round memory roundInfo = rounds[roundId];
        require(roundInfo.timestamp > 0, 'Invalid roundId');
        
        uint256 duration = block.timestamp - roundInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Dispute window is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Dispute window is 1 hour'); // dev

        uint256 totalAmount = roundInfo.totalAttackAmount + roundInfo.totalDefenseAmount;

        if (roundInfo.totalAttackAmount < roundInfo.totalDefenseAmount) {

            if (voteId > 0) {
                _mint(_msgSender(), totalAmount * voteInfo.amount / roundInfo.totalDefenseAmount);
            } else { // 1st defender
                _mint(_msgSender(), (totalAmount * voteInfo.amount / roundInfo.totalDefenseAmount) - voteInfo.amount);
            }
        }

        defenseVotes[roundId][voteId].voter = address(0);
    }
    
    function stake(uint256 id, uint256 amount) public {
    
        require(amount > 0, 'Cannot stake 0');
        require(id < totalOnnanocos, 'Character data is empty');
        require(onnanocos[id].status == Lib.Status.NORMAL, 'Round is not in normal status');

        _burn(_msgSender(), amount);

        stakes[_msgSender()].push(Lib.Stake(id, amount, block.timestamp));
        onnanocos[id].totalStakingAmount += amount;
    }
    
    function unstake(uint256 stakeId) public {

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];
        
        require(stakeInfo.timestamp > 0, 'Invalid stakeId');
        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'Round is in dispute status');
        
        (uint256 reward, uint256 duration) = getStakeRewardAmount(_msgSender(), stakeId);

        //require(duration > 60 * 60 * 24 * 100, 'Minimum duration is 100 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 hour'); // Test

        _mint(_msgSender(), stakeInfo.amount + reward);
        onnanocos[stakeInfo.id].totalStakingAmount -= stakeInfo.amount;
        delete stakes[_msgSender()][stakeId];
    }

    function getStakeRewardAmount(address staker, uint256 stakeId) public view returns(uint256 amount, uint256 duration) {

        Lib.Stake memory stakeInfo = stakes[staker][stakeId];

        duration = block.timestamp - stakeInfo.timestamp;
        amount = stakeInfo.amount * duration / (60 * 60 * 24 * 100);

        if (onnanocos[stakeInfo.id].status != Lib.Status.NORMAL) {
            return (0, 0);
        }

        return (amount, duration);
    }

    function receiveStakeReward(uint256 stakeId) public {

        (uint256 reward, uint256 duration) = getStakeRewardAmount(_msgSender(), stakeId);

        require(reward > 0, 'Reward must greater than 0');
        //require(duration > 60 * 60 * 24 * 100, 'Minimum duration is 100 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 hour'); // Test

        stakes[_msgSender()][stakeId].timestamp = block.timestamp;
        _mint(_msgSender(), reward);
    }

    function getOwnerRewardAmount(uint256 id) public view returns(uint256 amount, uint256 duration){

        Lib.Onnanoco memory onnanocoInfo = onnanocos[id];
        
        if (onnanocoInfo.timestamp == 0) {
            return (0, 0);
        }

        if (onnanocoInfo.status != Lib.Status.NORMAL) {
            return (0, 0);
        }

        Lib.Vote memory voteInfo = defenseVotes[onnanocoInfo.roundId][0];

        if (voteInfo.timestamp == 0) { // voteInfo is empty
            return (0, 0);
        }

        duration = block.timestamp - voteInfo.timestamp;
        amount = voteInfo.amount * duration / (60 * 60 * 24 * 50);

        return (amount, duration);
    }

    function receiveOwnerReward(uint256 id) public {
        
        require(defenseVotes[onnanocos[id].roundId][0].voter == _msgSender(), 'Permission denied');

        (uint256 reward, uint256 duration) = getOwnerRewardAmount(id);
        //require(duration > 60 * 60 * 24 * 50, 'Minimum duration is 50 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 hour'); // Test

        require(reward > 0, 'Reward must greater than 0');

        _mint(_msgSender(), reward);
        defenseVotes[onnanocos[id].roundId][0].timestamp = block.timestamp;
    }

    function deposit(address user, bytes calldata depositData) external override {

        require(hasRole(DEPOSITOR_ROLE, _msgSender()), "You're not allowed to deposit");
        
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

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