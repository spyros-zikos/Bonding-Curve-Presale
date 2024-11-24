// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC20Ownable} from "../src/ERC20Ownable.sol";

contract DeployERC20Ownable is Script {
    function run() external returns(address) {
        vm.startBroadcast();
        ERC20Ownable token = new ERC20Ownable("Name", "Symbol");
        vm.stopBroadcast();
        return address(token);
    }
}