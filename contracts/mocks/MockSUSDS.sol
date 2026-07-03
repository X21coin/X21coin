pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockSUSDS is ERC4626 {
    constructor(IERC20 asset_) ERC20("Mock sUSDS", "sUSDS") ERC4626(asset_) {}
}
