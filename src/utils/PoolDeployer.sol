// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BalancerPoolDeployer} from "../Balancer/BalancerPoolDeployer.sol";
import {UniswapPoolDeployer} from "../Uniswap/UniswapPoolDeployer.sol";


event UniswapPoolDeployed(address pool);
event BalancerPoolDeployed(address pool);


enum PoolType {
    Uniswap,
    Balancer
}


contract PoolDeployer is BalancerPoolDeployer, UniswapPoolDeployer {
    uint24 internal constant UNISWAP_SWAP_FEE = 3000;  // 0.3%, don't change this
    uint256 internal constant BALANCER_SWAP_FEE = 0.3e16;  // 0.3%

    constructor(
        // Uniswap
        address factory,
        address nonfungiblePositionManager,
        // Balancer
        address vault,
        address router,
        address CPFactory,
        address permit2
        )
        UniswapPoolDeployer(factory, nonfungiblePositionManager, UNISWAP_SWAP_FEE)
        BalancerPoolDeployer(vault, router, CPFactory, permit2, BALANCER_SWAP_FEE) 
    {}

    // Needs sorted tokens and amounts by token ascending order, use _sortTokens function
    function _deployPool(PoolType poolType, address token0, address token1, uint256 amount0, uint256 amount1) internal returns(address pool) {
        if (poolType == PoolType.Uniswap) {
            // Deploy uniswap pool and add the tokens
            uint256 tokenId;
            address nfpm;
            (pool, tokenId, nfpm) = deployUniswapPool(token0, token1, amount0, amount1);
            emit UniswapPoolDeployed(pool);
            // Burn liquidity NFT
            IERC721(nfpm).transferFrom(address(this), address(0xdEaD), tokenId);
        } else {
            // Deploy balancer pool and add the tokens
            pool = deployConstantProductPool(token0, token1, amount0, amount1);
            emit BalancerPoolDeployed(pool);
            // Burn BPT
            IERC20(pool).transfer(address(0xdEaD), IERC20(pool).balanceOf(address(this)));
        }
    }

    function _sortTokens(address token0, address token1, uint256 tokenAmount0, uint256 tokenAmount1) 
        internal pure returns (address _token0, address _token1, uint256 _tokenAmount0, uint256 _tokenAmount1)
    {
        (_token0, _token1, _tokenAmount0, _tokenAmount1) = token0 < token1
            ? (token0, token1, tokenAmount0, tokenAmount1)
            : (token1, token0, tokenAmount1, tokenAmount0);
    }
}

