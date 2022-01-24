// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IMOEToken {
    function deposit(address user, bytes calldata depositData) external;
}