// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

interface IBaseV1Factory {
    function protocolAddresses(address _pair) external returns (address);
    function spiritMaker() external returns (address);
    function stableFee() external returns (uint256);
    function variableFee() external returns (uint256);
    function getInitializable() external view returns (address, address, bool);
    function allPairsLength() external view returns (uint256);
    function isPair(address pair) external view returns (bool);
    function pairCodeHash() external pure returns (bytes32);
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function isPaused() external view returns (bool);
}
