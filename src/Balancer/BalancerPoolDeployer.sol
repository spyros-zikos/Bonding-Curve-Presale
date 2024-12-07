//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

import { PoolHelpers } from "src/Balancer/PoolHelpers.sol";
import { ConstantProductFactory } from "@balancer/scaffold-balancer-v3/packages/foundry/contracts/factories/ConstantProductFactory.sol";

/**
 * @title Deploy Constant Product Pool
 * @notice Deploys, registers, and initializes a constant product pool
 */
contract BalancerPoolDeployer is PoolHelpers {
    IVault internal vault;
    IRouter internal router;
    ConstantProductFactory internal factory;
    uint256 internal swapFee;

    constructor(address _vault, address _router, address _factory, address _permit2, uint256 _swapFee) PoolHelpers(_router, _permit2) {
        vault = IVault(_vault);
        router = IRouter(_router);
        factory = ConstantProductFactory(_factory);
        swapFee = _swapFee;
    }

    function deployConstantProductPool(address token1, address token2, uint256 amount1, uint256 amount2) internal returns(address) {
        // Deploy a pool and register it with the vault
        address pool = factory.create(
            "Constant Product Pool", // name for the pool
            "CPP", // symbol for the BPT
            keccak256(abi.encode(block.number)), // salt for the pool deployment via factory
            getTokenConfig(token1, token2),
            swapFee,
            false,
            PoolRoleAccounts({
                pauseManager: address(0), // Account empowered to pause/unpause the pool (or 0 to delegate to governance)
                swapFeeManager: address(0), // Account empowered to set static swap fees for a pool (or 0 to delegate to goverance)
                poolCreator: address(0) // Account empowered to set the pool creator fee percentage
            }),
            address(0),  // no hook
            LiquidityManagement({
                disableUnbalancedLiquidity: false,
                enableAddLiquidityCustom: false,
                enableRemoveLiquidityCustom: false,
                enableDonation: true
            })
        );

        IERC20[] memory tokens = new IERC20[](2); // Array of tokens to be used in the pool
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        uint256[] memory exactAmountsIn = new uint256[](2); // Exact amounts of tokens to be added, sorted in token alphanumeric order
        exactAmountsIn[0] = amount1; // amount of token1 to send during pool initialization
        exactAmountsIn[1] = amount2; // amount of token2 to send during pool initialization

        // Approve the router to spend tokens for pool initialization
        approveRouterWithPermit2(tokens);

        // Seed the pool with initial liquidity using Router as entrypoint
        router.initialize(
            pool,
            tokens,
            exactAmountsIn,
            0,
            false,
            bytes("")
        );

        return pool;
    }

    /**
     * @dev Set all of the configurations for deploying and registering a pool here
     * @notice TokenConfig encapsulates the data required for the Vault to support a token of the given type.
     * For STANDARD tokens, the rate provider address must be 0, and paysYieldFees must be false.
     * All WITH_RATE tokens need a rate provider, and may or may not be yield-bearing.
     */
    function getTokenConfig(
        address token1,
        address token2
    ) internal pure returns (TokenConfig[] memory tokenConfigs) {
        tokenConfigs = new TokenConfig[](2); // An array of descriptors for the tokens the pool will manage
        tokenConfigs[0] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token1),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });
        tokenConfigs[1] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token2),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });
    }
}
