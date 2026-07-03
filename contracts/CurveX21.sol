// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {X21} from "./X21.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CurveX21 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant SOURCE_VERSION = 2;
    uint256 public constant S_MAX = 20_895_000 ether;
    uint256 public constant RESERVE_TARGET = 2_000_000 ether;
    UD60x18 internal constant B = UD60x18.wrap(170_210_618_405);
    UD60x18 internal constant A_OVER_B = UD60x18.wrap(58_750_741_250_501_480_427_895);

    uint256 public constant FEE_BPS = 30;
    uint256 public constant BPS = 10_000;

    X21 public immutable coin;
    IERC20 public immutable usds;
    IERC4626 public immutable sUsds;

    uint256 public minted;
    bool public bonded;

    event Buy(address indexed to, uint256 usdsIn, uint256 coinOut, uint256 burned, uint256 minted);
    event Sell(address indexed from, uint256 coinIn, uint256 usdsOut, uint256 burned, uint256 minted);
    event Bonded(uint256 reserveUsds, uint256 supply);

    error Zero();
    error IssuanceClosed();
    error Slippage(uint256 got, uint256 min);

    constructor(IERC20 _usds, IERC4626 _sUsds) {
        usds = _usds;
        sUsds = _sUsds;
        coin = new X21(address(this));
        _usds.forceApprove(address(_sUsds), type(uint256).max);
    }

    function _expAt(uint256 supplyWei) internal pure returns (UD60x18) {
        return B.mul(UD60x18.wrap(supplyWei)).exp();
    }

    function costBetween(uint256 s1, uint256 s2) public pure returns (uint256) {
        return A_OVER_B.mul(_expAt(s2).sub(_expAt(s1))).unwrap();
    }

    function spotPrice() external view returns (uint256) {
        return A_OVER_B.mul(B).mul(_expAt(minted)).mul(_ratio()).unwrap();
    }

    function reserveUsds() public view returns (uint256) {
        return sUsds.convertToAssets(sUsds.balanceOf(address(this)));
    }

    function formulaReserve() public view returns (uint256) {
        return costBetween(0, minted);
    }

    function _ratio() internal view returns (UD60x18) {
        uint256 f = formulaReserve();
        if (f == 0) return ud(1e18);
        uint256 a = reserveUsds();
        if (a < f) a = f;
        return ud(a).div(ud(f));
    }

    function ratio() external view returns (uint256) {
        return _ratio().unwrap();
    }

    function quoteBuy(uint256 usdsIn)
        public
        view
        returns (uint256 coinOut, uint256 gross, uint256 burned, uint256 usdsUsed)
    {
        uint256 s1 = minted;
        UD60x18 r = _ratio();
        uint256 netForCurve = ud(usdsIn).div(r).unwrap();
        UD60x18 target = _expAt(s1).add(ud(netForCurve).div(A_OVER_B));
        uint256 s2 = target.ln().div(B).unwrap();
        if (s2 > S_MAX) s2 = S_MAX;
        gross = s2 - s1;

        usdsUsed = ud(costBetween(s1, s2)).mul(r).unwrap() + 1;
        if (usdsUsed > usdsIn) usdsUsed = usdsIn;

        burned = (gross * FEE_BPS) / BPS;
        coinOut = gross - burned;
    }

    function quoteSell(uint256 coinIn)
        public
        view
        returns (uint256 usdsOut, uint256 burned, uint256 redeemed)
    {
        burned = (coinIn * FEE_BPS) / BPS;
        redeemed = coinIn - burned;
        uint256 base = costBetween(minted - redeemed, minted);
        usdsOut = ud(base).mul(_ratio()).unwrap();
    }

    function buy(uint256 usdsIn, uint256 minOut, address to)
        external
        nonReentrant
        returns (uint256 coinOut)
    {
        if (bonded) revert IssuanceClosed();
        if (usdsIn == 0) revert Zero();

        uint256 gross;
        uint256 burned;
        uint256 usdsUsed;
        (coinOut, gross, burned, usdsUsed) = quoteBuy(usdsIn);
        if (coinOut < minOut) revert Slippage(coinOut, minOut);

        usds.safeTransferFrom(msg.sender, address(this), usdsIn);
        sUsds.deposit(usdsUsed, address(this));
        if (usdsIn > usdsUsed) usds.safeTransfer(msg.sender, usdsIn - usdsUsed);

        minted += gross;
        coin.mint(to, coinOut);

        emit Buy(to, usdsUsed, coinOut, burned, minted);
        if (minted >= S_MAX) {
            bonded = true;
            emit Bonded(reserveUsds(), minted);
        }
    }

    function sell(uint256 coinIn, uint256 minOut, address to)
        external
        nonReentrant
        returns (uint256 usdsOut)
    {
        if (coinIn == 0) revert Zero();

        uint256 burned;
        uint256 redeemed;
        (usdsOut, burned, redeemed) = quoteSell(coinIn);
        if (usdsOut < minOut) revert Slippage(usdsOut, minOut);
        uint256 res = reserveUsds();
        if (usdsOut > res) usdsOut = res;

        minted -= redeemed;
        coin.burn(msg.sender, coinIn);
        sUsds.withdraw(usdsOut, to, address(this));

        emit Sell(msg.sender, coinIn, usdsOut, burned, minted);
    }
}
