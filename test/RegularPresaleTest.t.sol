// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployERC20Ownable} from "../script/DeployERC20Ownable.s.sol";
import {RegularPresale} from "../src/RegularPresale.sol";

contract RegularPresaleTest {
    IERC20 token;
    function setUp() public {
        // Deploy Token
        DeployERC20Ownable deployToken = new DeployERC20Ownable();
        token = IERC20(deployToken.run());
        
    }

}