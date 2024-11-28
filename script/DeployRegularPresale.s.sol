// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {RegularPresale} from "../src/RegularPresale.sol";
import {DeployERC20Ownable} from "./DeployERC20Ownable.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployRegularPresale is Script {
    function run() external returns(RegularPresale, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.deployerKey);
        RegularPresale presale = new RegularPresale(
            config.creationFee,
            config.successfulEndFee,
            config.feeCollector,
            config.priceFeed,
            config.uniFactory,
            config.nonfungiblePositionManager,
            config.weth,  // from uniswap
            config.balancerVault,
            config.balancerRouter,
            config.balancerPermit2
        );
        vm.stopBroadcast();
        return (presale, helperConfig);
    }
}
