// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BondingCurvePresale} from "../src/BondingCurvePresale.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployBondingCurvePresale is Script {
    function run() external returns(BondingCurvePresale, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.deployerKey);
        BondingCurvePresale presale = new BondingCurvePresale(
            config.successfulEndFee,
            config.feeCollector,
            config.a,
            config.minInitialEthAmount,
            config.swapFee,
            config.uniFactory,
            config.nonfungiblePositionManager,
            config.weth
        );
        vm.stopBroadcast();
        return (presale, helperConfig);
    }
}
