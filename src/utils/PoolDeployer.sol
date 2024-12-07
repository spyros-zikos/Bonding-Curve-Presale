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
        address _factory,
        address _nonfungiblePositionManager,
        // Balancer
        address _vault,
        address _router,
        address _CPFactory,
        address _permit2
        )
        UniswapPoolDeployer(_factory, _nonfungiblePositionManager, UNISWAP_SWAP_FEE)
        BalancerPoolDeployer(_vault, _router, _CPFactory, _permit2, BALANCER_SWAP_FEE) 
    {}

    // Needs sorted tokens and amounts by token ascending order, use _sortTokens function
    function _deployPool(PoolType poolType, address _token0, address _token1, uint256 _amount0, uint256 _amount1) internal returns(address pool) {
        if (poolType == PoolType.Uniswap) {
            // Deploy uniswap pool and add the tokens
            uint256 tokenId;
            address nfpm;
            (pool, tokenId, nfpm) = deployUniswapPool(_token0, _token1, _amount0, _amount1);
            emit UniswapPoolDeployed(pool);
            // Burn liquidity NFT
            IERC721(nfpm).transferFrom(address(this), address(0xdEaD), tokenId);
        } else {
            // Deploy balancer pool and add the tokens
            pool = deployConstantProductPool(_token0, _token1, _amount0, _amount1);
            emit BalancerPoolDeployed(pool);
            // Burn BPT
            IERC20(pool).transfer(address(0xdEaD), IERC20(pool).balanceOf(address(this)));
        }
    }

    function _sortTokens(address _token0, address _token1, uint256 _tokenAmount0, uint256 _tokenAmount1) 
        internal pure returns (address token0, address token1, uint256 tokenAmount0, uint256 tokenAmount1)
    {
        (token0, token1, tokenAmount0, tokenAmount1) = 
            _token0 < _token1
            ? (_token0, _token1, _tokenAmount0, _tokenAmount1)
            : (_token1, _token0, _tokenAmount1, _tokenAmount0);
    }
}

