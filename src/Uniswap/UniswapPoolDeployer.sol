// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";


contract UniswapPoolDeployer {
    address private factory;
    address private nonfungiblePositionManager;
    uint24 private swapFee;

    constructor(address _factory, address _nonfungiblePositionManager, uint24 _swapFee) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapFee = _swapFee;
    }

    // Deploy Uniswap V3 Pool
    function deployUniswapPool(address token0, address token1, uint256 token0Amount, uint256 token1Amount) internal returns(address pool, uint256 tokenId, address nfpm) {
        // Create Uniswap v3 pool
        pool = IUniswapV3Factory(factory).createPool(token0, token1, swapFee);
        uint256 price = token1Amount * (2 ** 96) / token0Amount;
        uint160 sqrtPriceX96 = uint160(Math.sqrt(price) * (2 ** 48));
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        

        // Add liquidity to Uniswap v3 pool
        TransferHelper.safeApprove(token0, nonfungiblePositionManager, token0Amount);
        TransferHelper.safeApprove(token1, nonfungiblePositionManager, token1Amount);
        uint256 amount0Min = token0Amount * 99 / 100;  // 1% slippage
        uint256 amount1Min = token1Amount * 99 / 100;  // 1% slippage

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: swapFee,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: token0Amount,
                amount1Desired: token1Amount,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp
            });
        (tokenId,,,) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
        nfpm = nonfungiblePositionManager;
    }
}