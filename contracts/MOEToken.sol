// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Library.sol";
import "./IMOEToken.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract MOEToken is ContextUpgradeable, AccessControlEnumerableUpgradeable, IMOEToken, ERC20Upgradeable {

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    mapping(uint256 => Lib.Onnanoco) public onnanocos;
    mapping(uint256 => Lib.Round) public rounds;

    uint256 public totalRounds;
    uint256 public totalOnnanocos;

    mapping(uint256 => Lib.Vote[]) public defenseVotes;
    mapping(uint256 => Lib.Vote[]) public attackVotes;
    mapping(address => Lib.Stake[]) public stakes;

    function add(string memory name, bytes32 hash, bytes2 hashFunction, uint8 hashSize, uint256 amount) public {
        
        require(amount > 0, 'MOE: amount cannot be 0');
        require(amount <= balanceOf(_msgSender()), 'MOE: not enough MOE');

        _burn(_msgSender(), amount);

        onnanocos[totalOnnanocos] = Lib.Onnanoco(name, _msgSender(), Lib.Multihash(hash, hashFunction, hashSize), Lib.Status.NORMAL, block.timestamp, 0, totalRounds);

        rounds[totalRounds] = Lib.Round(totalOnnanocos, amount, 0, 0, 1);

        defenseVotes[totalRounds].push(Lib.Vote(totalOnnanocos, _msgSender(), amount, block.timestamp, ''));

        totalOnnanocos++;
        totalRounds++;
    }

    function getMinimumAttackAmount(uint256 id) public view returns (uint256 amount) {

        require(id < totalOnnanocos, 'MOE: no onnanoco data available');
        require(onnanocos[id].status != Lib.Status.DEPRECATED, 'MOE: deprecated data');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];

        if (((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) > (roundInfo.totalAttackAmount * 3)) {
            return ((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) - (roundInfo.totalAttackAmount * 3);
        } else {
            return 0;
        }
    }

    function attack(uint256 id, uint256 amount, string memory evidence) public {

        require(amount > 0, 'MOE: amount cannot be 0');
        require(amount <= balanceOf(_msgSender()), 'MOE: not enough MOE');
        
        uint256 minimumAmount = getMinimumAttackAmount(id);
        require(amount >= minimumAmount, 'MOE: less than minimum amount');

        uint256 roundId = onnanocos[id].roundId;
        
        if (onnanocos[id].status == Lib.Status.NORMAL) {

            onnanocos[id].status = Lib.Status.IN_DISPUTE;
            rounds[roundId].timestamp = block.timestamp;

        } else {
            
            Lib.Round memory roundInfo = rounds[roundId];
            require(roundInfo.timestamp > 0, 'MOE: no round data available');

            uint256 duration = block.timestamp - roundInfo.timestamp;
            require(duration < 60 * 60 * 24 * 7, 'MOE: round is not in dispute');
        }

        _burn(_msgSender(), amount);
        attackVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp, evidence));

        rounds[roundId].totalAttackAmount += amount;
        rounds[roundId].totalVotes++;
    }

    function getMinimumDefenseAmount(uint256 id) public view returns (uint256 amount) {

        require (id < totalOnnanocos, 'MOE: no onnanoco data available');
        require (onnanocos[id].status == Lib.Status.IN_DISPUTE, 'MOE: round is not in dispute');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];
        require(roundInfo.timestamp > 0, 'MOE: no round data available');

        if (((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) > (roundInfo.totalDefenseAmount * 3)) {
            return ((roundInfo.totalDefenseAmount + roundInfo.totalAttackAmount) * 2) - (roundInfo.totalDefenseAmount * 3);
        } else {
            return 0;
        }
    }

    function defense(uint256 id, uint256 amount, string memory evidence) public {

        require(amount > 0, 'MOE: amount cannot be 0');
        require(amount <= balanceOf(_msgSender()), 'MOE: not enough MOE');

        uint256 roundId = onnanocos[id].roundId;
        Lib.Round memory roundInfo = rounds[roundId];

        uint256 minimumAmount = getMinimumDefenseAmount(id);
        require(amount >= minimumAmount, 'MOE: less than minimum amount');

        uint256 duration = block.timestamp - roundInfo.timestamp;
        require(duration < 60 * 60 * 24 * 7, 'MOE: round is not in dispute');

        _burn(_msgSender(), amount);
        defenseVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp, evidence));

        rounds[roundId].totalDefenseAmount += amount;
        rounds[roundId].totalVotes++;
    }

    function clearRound(uint256 roundId) public {
        
        require(roundId < totalRounds, 'MOE: no round data available');

        Lib.Round memory roundInfo = rounds[roundId];
        Lib.Onnanoco storage onnanoco = onnanocos[roundInfo.onnanocoId];
        require(onnanoco.status == Lib.Status.IN_DISPUTE, 'MOE: round is not in dispute');

        uint256 duration = block.timestamp - roundInfo.timestamp;
        require(duration > 60 * 60 * 24 * 7, 'MOE: dispute window is not over');

        if (roundInfo.totalAttackAmount > roundInfo.totalDefenseAmount) { // Attackers win
            _mint(_msgSender(), roundInfo.totalAttackAmount / 100 * 1);
            onnanoco.status = Lib.Status.DEPRECATED;

        } else if(roundInfo.totalAttackAmount < roundInfo.totalDefenseAmount) { // Attackers lose
            _mint(_msgSender(), roundInfo.totalDefenseAmount / 100 * 1);
            onnanoco.status = Lib.Status.NORMAL;

            Lib.Vote memory vote = defenseVotes[roundId][0];

            rounds[totalRounds] = Lib.Round(roundInfo.onnanocoId, vote.amount, 0, 0, 1);
            onnanoco.roundId = totalRounds;

            defenseVotes[totalRounds].push(Lib.Vote(roundInfo.onnanocoId, vote.voter, vote.amount, block.timestamp, ''));

            totalRounds++;
        }
    }

    function resolveAttack(uint256 roundId, uint256 voteId) public {

        require(roundId < totalRounds, 'MOE: no round data available');
        require(voteId < attackVotes[roundId].length, 'MOE: no attack data available');

        Lib.Vote memory voteInfo = attackVotes[roundId][voteId];
        require(_msgSender() == voteInfo.voter, 'MOE: access denied');

        Lib.Round memory roundInfo = rounds[roundId];
        uint256 duration = block.timestamp - roundInfo.timestamp;
        require(duration > 60 * 60 * 24 * 7, 'MOE: dispute window is not over');

        uint256 totalAmount = roundInfo.totalAttackAmount + roundInfo.totalDefenseAmount;

        if (roundInfo.totalAttackAmount > roundInfo.totalDefenseAmount) {
            _mint(_msgSender(), totalAmount * voteInfo.amount / roundInfo.totalAttackAmount);
        }

        attackVotes[roundId][voteId].voter = address(0);
    }

    function resolveDefense(uint256 roundId, uint256 voteId) public {

        require(roundId < totalRounds, 'MOE: no round data available');
        require(voteId < defenseVotes[roundId].length, 'MOE: no defense data available');

        Lib.Vote memory voteInfo = defenseVotes[roundId][voteId];
        require(_msgSender() == voteInfo.voter, 'MOE: access denied');

        Lib.Round memory roundInfo = rounds[roundId];
        uint256 duration = block.timestamp - roundInfo.timestamp;
        require(duration > 60 * 60 * 24 * 7, 'MOE: dispute window is not over');

        uint256 totalAmount = roundInfo.totalAttackAmount + roundInfo.totalDefenseAmount;

        if (roundInfo.totalAttackAmount < roundInfo.totalDefenseAmount) {

            if (voteId > 0) {
                _mint(_msgSender(), totalAmount * voteInfo.amount / roundInfo.totalDefenseAmount);
            } else {
                _mint(_msgSender(), (totalAmount * voteInfo.amount / roundInfo.totalDefenseAmount) - voteInfo.amount);
            }
        }

        defenseVotes[roundId][voteId].voter = address(0);
    }
    
    function stake(uint256 id, uint256 amount) public {
    
        require(amount > 0, 'MOE: amount cannot be 0');
        require(amount <= balanceOf(_msgSender()), 'MOE: not enough MOE');
        require(id < totalOnnanocos, 'MOE: no onnanoco data available');
        require(onnanocos[id].status == Lib.Status.NORMAL, 'MOE: round is not in normal status');

        _burn(_msgSender(), amount);

        stakes[_msgSender()].push(Lib.Stake(id, amount, block.timestamp));
        onnanocos[id].totalStakingAmount += amount;
    }
    
    function unstake(uint256 stakeId) public {

        (uint256 reward, uint256 duration) = getStakingRewardsAmount(_msgSender(), stakeId);

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];
        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'MOE: round is in dispute status');
        
        require(duration > 60 * 60 * 24 * 100, 'MOE: request can be made after at least 100 days');

        _mint(_msgSender(), stakeInfo.amount + reward);
        onnanocos[stakeInfo.id].totalStakingAmount -= stakeInfo.amount;

        for (uint256 i = stakeId; i < stakes[_msgSender()].length - 1; i++) {
            stakes[_msgSender()][i] = stakes[_msgSender()][i + 1];
            stakes[_msgSender()].pop();
        }
    }

    function getStakingRewardsAmount(address staker, uint256 stakeId) public view returns(uint256 amount, uint256 duration) {

        require(stakes[_msgSender()].length > 0, 'MOE: no staking data available');
        require(stakes[_msgSender()].length > stakeId, 'MOE: no staking data available');

        Lib.Stake memory stakeInfo = stakes[staker][stakeId];
        require(onnanocos[stakeInfo.id].status == Lib.Status.NORMAL, 'MOE: round is not in normal status');

        duration = block.timestamp - stakeInfo.timestamp;
        amount = stakeInfo.amount * duration / (60 * 60 * 24 * 100);

        return (amount, duration);
    }

    function receiveStakingRewards(uint256 stakeId) public {

        (uint256 reward, uint256 duration) = getStakingRewardsAmount(_msgSender(), stakeId);

        require(reward > 0, 'MOE: reward must greater than 0');
        require(duration > 60 * 60 * 24 * 100, 'MOE: request can be made after at least 100 days');

        stakes[_msgSender()][stakeId].timestamp = block.timestamp;
        _mint(_msgSender(), reward);
    }

    function getOwnerRewardsAmount(uint256 id) public view returns(uint256 amount, uint256 duration){

        require(id < totalOnnanocos, 'MOE: no onnanoco data available');

        Lib.Onnanoco memory onnanocoInfo = onnanocos[id];
        require(onnanocoInfo.status == Lib.Status.NORMAL, 'MOE: round is not in normal status');

        Lib.Vote memory voteInfo = defenseVotes[onnanocoInfo.roundId][0];

        duration = block.timestamp - voteInfo.timestamp;
        amount = voteInfo.amount * duration / (60 * 60 * 24 * 50);

        return (amount, duration);
    }

    function receiveOwnerRewards(uint256 id) public {
        
        (uint256 reward, uint256 duration) = getOwnerRewardsAmount(id);

        require(onnanocos[id].owner == _msgSender(), 'MOE: access denied');
        require(duration > 60 * 60 * 24 * 50, 'MOE: request can be made after at least 50 days');
        require(reward > 0, 'MOE: reward must greater than 0');

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
    function initialize(string memory name, string memory symbol, address childchaninProxy) public virtual initializer {

        __ERC20_init(name, symbol);
        _setupRole(DEPOSITOR_ROLE, childchaninProxy);
    }
}