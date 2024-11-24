// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {RegularPresale} from "../src/RegularPresale.sol";
import {DeployERC20Ownable} from "./DeployERC20Ownable.s.sol";

contract DeployRegularPresale is Script {
    function run() external returns(RegularPresale) {
        vm.startBroadcast();
        RegularPresale presale = new RegularPresale();
        vm.stopBroadcast();
        return presale;
    }
}

// contract DeployRegularPresaleAndCreatePresale is Script {
//     function run() external {
//         vm.startBroadcast();
//         RegularPresale presale = (new DeployRegularPresale()).run();
//         address token = (new DeployERC20Ownable()).run();
//         presale.createPresale(token, 0, 0, 0, 0, 0);
//         vm.stopBroadcast();
//     }
// }