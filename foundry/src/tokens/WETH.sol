// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Detailed} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Detailed.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

contract WrappedEth is ERC20, ERC20Detailed, ERC20Pausable {
    uint256 public constant ERR_NO_ERROR = 0x0;
    uint256 public constant ERR_INVALID_ZERO_VALUE = 0x01;

    constructor() ERC20Detailed("Wrapped Ether", "WETH", 18) {}

    function deposit() public payable whenNotPaused returns (uint256) {
        if (msg.value == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }

        _mint(msg.sender, msg.value);

        return ERR_NO_ERROR;
    }

    function withdraw(uint256 amount) public whenNotPaused returns (uint256) {
        if (amount == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }

        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);

        return ERR_NO_ERROR;
    }
}
