// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract X21 is ERC20 {
    uint256 public constant SOURCE_VERSION = 2;
    uint256 public constant MAX_SUPPLY = 21_000_000 ether;

    address public immutable curve;

    error OnlyCurve();
    error CapExceeded();

    constructor(address _curve) ERC20("X21", "X21") {
        curve = _curve;
    }

    modifier onlyCurve() {
        if (msg.sender != curve) revert OnlyCurve();
        _;
    }

    function mint(address to, uint256 amount) external onlyCurve {
        if (totalSupply() + amount > MAX_SUPPLY) revert CapExceeded();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyCurve {
        _burn(from, amount);
    }
}
