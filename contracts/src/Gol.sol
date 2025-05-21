// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Gol is ERC20 {
    address private immutable i_owner;
    uint256 private constant TOTAL_SUPPLY = 100 ether;
    uint8 private constant DECIMALS = 18;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        i_owner = msg.sender;
        _mint(i_owner, TOTAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
