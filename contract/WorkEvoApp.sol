// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract WorkEvoApp is ERC20, Ownable {
    event TransactionCompleted(bytes32 messageHash);
    using EnumerableSet for EnumerableSet.AddressSet;
    address payable public systemAddress;
    uint256 public lockSignature = 5 minutes;
    mapping(bytes32 => uint256) public signIds;
    bytes32[] public ids;
    using ECDSA for bytes32;

    struct VestingSchedule {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool released;
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    EnumerableSet.AddressSet private investors;

    constructor(uint256 initialSupply, address payable initialOwner) ERC20("WorkEvoApp", "WEA") Ownable(initialOwner) {
        _mint(address(this), initialSupply);
        systemAddress = initialOwner;
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function grantTokens(uint256 amount, uint256 price, uint256 lockDuration, uint256 timestamp, bytes memory signature) public payable {
        require(msg.value >= price, "Wrong price");
        require(timestamp + lockSignature > block.timestamp, "Signature has expired");
        bytes32 messageHash = keccak256(abi.encodePacked(amount, price, lockDuration, timestamp, msg.sender));
        require(signIds[messageHash] == 0, "Signature already used");
        require(recoverSigner(messageHash, signature) == systemAddress, "Invalid signature");        

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (lockDuration * 1 minutes);

        vestingSchedules[msg.sender] = VestingSchedule(amount, startTime, endTime, false);
        investors.add(msg.sender);

        // Transfer excess ETH back to the sender
        if (msg.value > price) {
            uint256 excessAmount = msg.value - price;
            payable(msg.sender).transfer(excessAmount);
        }

        uint256 transferAmount = price;
        systemAddress.transfer(transferAmount);
    }

    function releaseTokens() external {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(block.timestamp >= schedule.endTime, "Tokens are still locked");
        require(!schedule.released, "Tokens have already been released");
        require(schedule.amount > 0, "No tokens to release");

        schedule.released = true;
        _transfer(address(this), msg.sender, schedule.amount);
    }

    function getVestingSchedule(address investor) external view returns (uint256, uint256, uint256, bool) {
        VestingSchedule memory schedule = vestingSchedules[investor];
        return (schedule.amount, schedule.startTime, schedule.endTime, schedule.released);
    }

    function getInvestors() external view returns (address[] memory) {
        return investors.values();
    }

    function successTransaction(bytes32 messageHash) external view returns (bool) {
        return !(signIds[messageHash] == 0);
    }

    function transfer(uint256 amount, uint256 price, uint256 timestamp, bytes memory signature) public payable {
        uint256 transferAmount = price;
        require(msg.value >= transferAmount, "Wrong price");
        require(timestamp + lockSignature > block.timestamp, "Signature has expired");
        bytes32 messageHash = keccak256(abi.encodePacked(amount, price, timestamp, msg.sender));
        require(signIds[messageHash] == 0, "Signature already used");
        require(recoverSigner(messageHash, signature) == systemAddress, "Invalid signature");
        signIds[messageHash] = timestamp + lockSignature;
        ids.push(messageHash);
        clearExpiredSignIds();

        // Transfer excess ETH back to the sender
        if (msg.value > transferAmount) {
            uint256 excessAmount = msg.value - transferAmount;
            payable(msg.sender).transfer(excessAmount);
        }

        systemAddress.transfer(transferAmount);

    	if (amount > 0) {
            _transfer(address(this), msg.sender, amount);
    	}
        emit TransactionCompleted(messageHash);
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address) {
        return MessageHashUtils.toEthSignedMessageHash(messageHash).recover(signature);
    }

    function clearExpiredSignIds() internal {
        uint256 nowTimestamp = block.timestamp;
        for (uint256 i = ids.length; i > 0; i--) {
            bytes32 id = ids[i - 1];
            if (signIds[id] != 0 && nowTimestamp > signIds[id]) {
                delete signIds[id];

                ids[i - 1] = ids[ids.length - 1];
                ids.pop();
            }
        }
    }
}



