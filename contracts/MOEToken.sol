// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./IChildToken.sol";
import "./Library.sol";

// *** IMPORTANT ***
//
// BEFORE DEPLOY
// --------------
// erase _mint() line on constructor function
// change duration require() function on unstake()
// change duration require() function on resolveAttack()
// change duration require() function on resolveDefense()
//
contract MOEToken is Context, AccessControlEnumerable, IChildToken, ERC20 {

    string public constant NAME = "MOE Token";
    string public constant SYMBOL = "MOE";
    uint8 public constant DECIMALS = 18;

    mapping(uint256 => Lib.Onnanoco) public onnanocos;
    mapping(uint256 => Lib.Round) public rounds;

    uint256 public totalRounds;
    uint256 public totalOnnanocos;

    mapping(uint256 => Lib.Vote[]) public defenseVotes;
    mapping(uint256 => Lib.Vote[]) public attackVotes;

    mapping(address => Lib.Stake[]) public stakes;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE"); // Polygon mapping

    // Contstructor
    constructor (string memory name, string memory symbol, address childChainManager) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, childChainManager);
        // test
        _mint(_msgSender(), 10**18 * 100);
    }

    // Polygon mapping : deposit
    function deposit(address user, bytes calldata depositData) external override {
        require(hasRole(DEPOSITOR_ROLE, _msgSender()), "You're not allowed to deposit");
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }


    // Add onnanoco
    // name: name of the character
    // hash, hashFunction, hashSize: multihash
    // amount: defense amount
    function addOnnanoco(string memory name, bytes32 hash, bytes2 hashFunction, uint8 hashSize, uint256 amount) public {
        //require(amount < balanceOf(_msgSender()), 'MOE: not enough MOE');

        _burn(_msgSender(), amount);

        // add onnanoco base data
        onnanocos[totalOnnanocos] = Lib.Onnanoco(name, _msgSender(), Lib.Multihash(hash, hashFunction, hashSize), Lib.Status.NORMAL, block.timestamp, 0, totalRounds);

        // setup round
        rounds[totalRounds] = Lib.Round(totalOnnanocos, amount, 0, block.timestamp);

        // vote for defense
        Lib.Vote memory vote = Lib.Vote(totalOnnanocos, _msgSender(), amount, block.timestamp);
        defenseVotes[totalRounds].push(vote);

        // increase onnanoco index
        totalOnnanocos++;
        totalRounds++;
    }

    // Vote for attack
    // id: id of the character
    // amount: defense amount
    function voteForAttack(uint256 id, uint256 amount) public {

        require(amount > 0, 'Cannot vote with 0 MOE');
        require(onnanocos[id].status != Lib.Status.DEPRECATED, 'Deprecated');

        uint256 roundId = onnanocos[id].roundId;

        uint256 totalDefenseAmount = rounds[roundId].totalDefenseAmount;
        uint256 totalAttackAmount = rounds[roundId].totalAttackAmount;

        require(amount >= (2 * (totalDefenseAmount + totalAttackAmount)) - (3 * totalAttackAmount), 'Not enough MOE');

        _burn(_msgSender(), amount);

        // 1st attack
        if (onnanocos[id].status == Lib.Status.NORMAL) {
            onnanocos[id].status = Lib.Status.IN_DISPUTE;
        }

        attackVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));
        rounds[roundId].totalAttackAmount += amount;
    }

    // Vote for defense
    // id: id of the character
    // amount: defense amount
    function voteForDefense(uint256 id, uint256 amount) public {

        require(amount > 0, 'Cannot vote with 0 MOE');
        require(onnanocos[id].status == Lib.Status.IN_DISPUTE, 'Round is not in dispute');

        uint256 roundId = onnanocos[id].roundId;

        uint256 totalDefenseAmount = rounds[roundId].totalDefenseAmount;
        uint256 totalAttackAmount = rounds[roundId].totalAttackAmount;

        require(amount >= (2 * (totalDefenseAmount + totalAttackAmount)) - (3 * totalDefenseAmount), 'Not enough MOE');

        _burn(_msgSender(), amount);
        defenseVotes[roundId].push(Lib.Vote(id, _msgSender(), amount, block.timestamp));

        rounds[roundId].totalDefenseAmount += amount;
    }

    function resolveAttack(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = attackVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Minimum duration is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 days'); // dev

        uint256 totalAmount = round.totalAttackAmount + round.totalDefenseAmount;

        if (round.totalAttackAmount > round.totalDefenseAmount) {
            _mint(_msgSender(), totalAmount * vote.amount / round.totalAttackAmount);
            attackVotes[roundId][voteId].voter = address(0);
            onnanocos[round.onnanocoId].status = Lib.Status.DEPRECATED;

        } else {
            attackVotes[roundId][voteId].voter = address(0);
        }

    }

    function resolveDefense(uint256 roundId, uint256 voteId) public {

        Lib.Vote memory vote = defenseVotes[roundId][voteId];
        Lib.Round memory round = rounds[roundId];

        require(_msgSender() == vote.voter, 'Access denied');

        uint256 duration = block.timestamp - round.timestamp;

        //require(duration > 60 * 60 * 24 * 7, 'Minimum duration is 7 days'); // deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 1 days'); // dev

        uint256 totalAmount = round.totalAttackAmount + round.totalDefenseAmount;

        if (round.totalAttackAmount < round.totalDefenseAmount) {
            _mint(_msgSender(), totalAmount * vote.amount / round.totalDefenseAmount);
            defenseVotes[roundId][voteId].voter = address(0);
            onnanocos[round.onnanocoId].status = Lib.Status.NORMAL;

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
        onnanocos[id].totalStakingAmount += amount;
    }
    
    // Unstake MOE
    function unstake(uint256 stakeId) public {

        Lib.Stake memory stakeInfo = stakes[_msgSender()][stakeId];
        
        require(onnanocos[stakeInfo.id].status != Lib.Status.IN_DISPUTE, 'Round is in dispute status');
        
        uint256 duration = block.timestamp - stakeInfo.timestamp;

        //require(duration > 60 * 60 * 24 * 100, 'Minimum duration is 100 days'); // Deploy
        require(duration > 60 * 60 * 1, 'Minimum duration is 100 days'); // Test

        uint256 bonus = stakeInfo.amount * duration * 5 / (60 * 60 * 24 * 100 * 100);

        if (onnanocos[stakeInfo.id].status == Lib.Status.DEPRECATED) {
            bonus = 0;
        }

        _mint(_msgSender(), stakeInfo.amount + bonus);
        onnanocos[stakeInfo.id].totalStakingAmount -= stakeInfo.amount;
    }

    /*
    // get onnanoco info
    function getOnnanoco(uint256 id) public view returns(Lib.Onnanoco memory) {
        return onnanocos[id];
    }

    // get stake list
    function getStakes() public view returns(Lib.Stake[] memory) {
        return stakes[_msgSender()];
    }
    */

    // Polygon mapping : withdraw
    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}