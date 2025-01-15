// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {UniswapPoolDeployer} from "../Uniswap/UniswapPoolDeployer.sol";


event UniswapPoolDeployed(address pool);


contract PoolDeployer is UniswapPoolDeployer {
    uint24 internal constant UNISWAP_SWAP_FEE = 3000;  // 0.3%, don't change this

    constructor(
        address factory,
        address nonfungiblePositionManager
    )
        UniswapPoolDeployer(factory, nonfungiblePositionManager, UNISWAP_SWAP_FEE)
    {}

    // Needs sorted tokens and amounts by token ascending order, use _sortTokens function
    function _deployPool(address token0, address token1, uint256 amount0, uint256 amount1) internal returns(address pool) {
        // Deploy uniswap pool and add the tokens
        uint256 tokenId;
        address nfpm;
        (pool, tokenId, nfpm) = deployUniswapPool(token0, token1, amount0, amount1);
        // Burn liquidity NFT
        IERC721(nfpm).transferFrom(address(this), address(0xdEaD), tokenId);
        emit UniswapPoolDeployed(pool);
    }

    function _sortTokens(address token0, address token1, uint256 tokenAmount0, uint256 tokenAmount1) 
        internal pure returns (address _token0, address _token1, uint256 _tokenAmount0, uint256 _tokenAmount1)
    {
        (_token0, _token1, _tokenAmount0, _tokenAmount1) = token0 < token1
            ? (token0, token1, tokenAmount0, tokenAmount1)
            : (token1, token0, tokenAmount1, tokenAmount0);
    }
}

