// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Ownable} from "../src/ERC20Ownable.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployERC20Ownable is Script {
    function run() external returns(address) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.deployerKey);
        ERC20Ownable token = new ERC20Ownable("Name", "Symbol");
        console.log("token address: ", address(token));
        token.mint(address(uint160(vm.envUint("PROJECT_CREATOR_ADDRESS"))), 1000e18);
        vm.stopBroadcast();
        return address(token);
    }
}