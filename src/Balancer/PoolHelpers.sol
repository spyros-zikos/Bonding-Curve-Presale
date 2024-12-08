// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

/**
 * @title Pool Helpers
 * @notice Helpful functions for deploying pools on Balancer v3
 */
contract PoolHelpers {
    IRouter private immutable i_router;
    IPermit2 private immutable i_permit2;

    constructor(address router, address permit2) {
        i_router = IRouter(router);
        i_permit2 = IPermit2(permit2);
    }

    /**
     * Sorts the tokenConfig array into alphanumeric order
     */
    function sortTokenConfig(TokenConfig[] memory tokenConfig) internal pure returns (TokenConfig[] memory) {
        if (tokenConfig[0].token > tokenConfig[1].token) {
            // Swap if they're out of order.
            (tokenConfig[0], tokenConfig[1]) = (tokenConfig[1], tokenConfig[0]);
        }
        return tokenConfig;
    }

    /**
     * @notice Approve permit2 on the token contract, then approve the router on the Permit2 contract
     * @param tokens Array of tokens to approve the router to spend using Permit2
     */
    function approveRouterWithPermit2(IERC20[] memory tokens) internal {
        tokens[0].approve(address(i_permit2), type(uint256).max);
        tokens[1].approve(address(i_permit2), type(uint256).max);
        i_permit2.approve(address(tokens[0]), address(i_router), type(uint160).max, type(uint48).max);
        i_permit2.approve(address(tokens[1]), address(i_router), type(uint160).max, type(uint48).max);
    }
}