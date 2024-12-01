// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ConstantProductFactory } from "@balancer/scaffold-balancer-v3/packages/foundry/contracts/factories/ConstantProductFactory.sol";
import { Script } from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

contract DeployConstantProductFactory is Script{
    function run() external returns(ConstantProductFactory, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.deployerKey);
        ConstantProductFactory factory = new ConstantProductFactory(IVault(config.balancerVault), 365 days);
        vm.stopBroadcast();
        return (factory, helperConfig);
    }
}