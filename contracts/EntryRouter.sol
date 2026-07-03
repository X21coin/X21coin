// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CurveX21} from "./CurveX21.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256 amountOut);
}

interface ILitePSM {
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 usdsOutWad);
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 usdsInWad);
}

contract EntryRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant SOURCE_VERSION = 2;
    CurveX21 public immutable curve;
    IERC20 public immutable coin;
    IERC20 public immutable usds;
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;
    IERC20 public immutable weth;
    ISwapRouter02 public immutable swap;
    ILitePSM public immutable psm;
    uint24 public constant POOL_FEE = 500;

    constructor(
        CurveX21 _curve,
        IERC20 _usds,
        IERC20 _usdc,
        IERC20 _usdt,
        IERC20 _weth,
        ISwapRouter02 _swap,
        ILitePSM _psm
    ) {
        curve = _curve;
        coin = IERC20(address(_curve.coin()));
        usds = _usds;
        usdc = _usdc;
        usdt = _usdt;
        weth = _weth;
        swap = _swap;
        psm = _psm;
        _usds.forceApprove(address(_curve), type(uint256).max);
        _usdc.forceApprove(address(_psm), type(uint256).max);
        _usds.forceApprove(address(_psm), type(uint256).max);
    }

    function buyWithUSDC(uint256 usdcIn, uint256 minCoinOut) external nonReentrant returns (uint256) {
        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        return _usdcToCoin(usdcIn, minCoinOut, msg.sender);
    }

    function buyWithUSDT(uint256 usdtIn, uint256 minUsdcOut, uint256 minCoinOut) external nonReentrant returns (uint256) {
        usdt.safeTransferFrom(msg.sender, address(this), usdtIn);
        usdt.forceApprove(address(swap), usdtIn);
        uint256 usdcOut = swap.exactInputSingle(ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(usdt), tokenOut: address(usdc), fee: 100,
            recipient: address(this), amountIn: usdtIn, amountOutMinimum: minUsdcOut, sqrtPriceLimitX96: 0
        }));
        return _usdcToCoin(usdcOut, minCoinOut, msg.sender);
    }

    function buyWithETH(uint256 minUsdcOut, uint256 minCoinOut) external payable nonReentrant returns (uint256) {
        uint256 usdcOut = swap.exactInputSingle{value: msg.value}(ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(weth), tokenOut: address(usdc), fee: POOL_FEE,
            recipient: address(this), amountIn: msg.value, amountOutMinimum: minUsdcOut, sqrtPriceLimitX96: 0
        }));
        return _usdcToCoin(usdcOut, minCoinOut, msg.sender);
    }

    function _usdcToCoin(uint256 usdcAmount, uint256 minCoinOut, address to) internal returns (uint256) {
        uint256 before = usds.balanceOf(address(this));
        psm.sellGem(address(this), usdcAmount);
        uint256 usdsAmount = usds.balanceOf(address(this)) - before;
        return curve.buy(usdsAmount, minCoinOut, to);
    }

    function sellForUSDC(uint256 coinIn, uint256 minUsdsOut, uint256 minUsdcOut) external nonReentrant returns (uint256) {
        coin.safeTransferFrom(msg.sender, address(this), coinIn);
        coin.forceApprove(address(curve), coinIn);
        uint256 usdsOut = curve.sell(coinIn, minUsdsOut, address(this));
        uint256 usdcOut = usdsOut / 1e12;
        require(usdcOut >= minUsdcOut, "slippage");
        psm.buyGem(msg.sender, usdcOut);
        return usdcOut;
    }

    receive() external payable {}
}
