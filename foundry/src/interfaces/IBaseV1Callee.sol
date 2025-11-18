// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

interface IBaseV1Callee {
    function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
