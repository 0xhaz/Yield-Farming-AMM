// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

interface IWFTM {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256 wad) external;
}
