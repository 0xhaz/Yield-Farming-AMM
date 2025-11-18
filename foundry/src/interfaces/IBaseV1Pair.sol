// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

interface IBaseV1Pair {
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function mint(address to) external returns (uint256 liquidity);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut);
}
