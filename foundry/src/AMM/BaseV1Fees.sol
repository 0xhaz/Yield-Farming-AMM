// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IBaseV1Factory} from "src/interfaces/IBaseV1Factory.sol";

/**
 * @title BaseV1 Fees Contract
 * @notice Base V1 Fees contract is used as a 1:1 pair relationship to split out fees, this ensures that the curve does not need to be modified for LP shares
 */
contract BaseV1Fees {
    /// @notice Factory that created the pairs
    address internal immutable i_factory;
    /// @notice The pair it is bonded to
    address internal immutable i_pair;
    /// @notice token0 of pair, saved locally and statically for gas savings
    address internal immutable i_token0;
    /// @notice token1 of pair, saved locally and statically for gas savings
    address internal immutable i_token1;

    constructor(address _token0, address _token1, address _factory) {
        i_pair = msg.sender;
        i_factory = _factory;
        i_token0 = _token0;
        i_token1 = _token1;
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    /**
     * @notice Allow the pair to transfer fees to users
     * @param recipient The address of the recipient
     * @param amount0 The amount of token0 to transfer
     * @param amount1 The amount of token1 to transfer
     * @return claimed0 The amount of token0 claimed
     * @return claimed1 The amount of token1 claimed
     */
    function claimFeesFor(address recipient, uint256 amount0, uint256 amount1)
        external
        returns (uint256 claimed0, uint256 claimed1)
    {
        require(msg.sender == i_pair);
        uint256 counter = 4;
        // send 25% to protocol address if protocol address exists
        address protocolAddress = IBaseV1Factory(i_factory).protocolAddresses(i_pair);
        if (protocolAddress != address(0)) {
            if (amount0 > 0) _safeTransfer(i_token0, protocolAddress, amount0 / 4);
            if (amount1 > 0) _safeTransfer(i_token1, protocolAddress, amount1 / 4);
            counter -= 1;
        }
        // send 25% to spiritMaker
        address spiritMaker = IBaseV1Factory(i_factory).spiritMaker();
        if (spiritMaker != address(0)) {
            if (amount0 > 0) _safeTransfer(i_token0, spiritMaker, amount0 / 4);
            if (amount1 > 0) _safeTransfer(i_token1, spiritMaker, amount1 / 4);
            counter -= 1;
        }
        claimed0 = amount0 * counter / 4;
        claimed1 = amount1 * counter / 4;
        // send the rest to the owner of LP
        if (amount0 > 0) _safeTransfer(i_token0, recipient, claimed0);
        if (amount1 > 0) _safeTransfer(i_token1, recipient, claimed1);
    }
}
