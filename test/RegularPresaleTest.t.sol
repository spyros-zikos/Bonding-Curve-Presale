// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployERC20Ownable} from "../script/DeployERC20Ownable.s.sol";
import {RegularPresale, PoolType} from "../src/RegularPresale.sol";
import {DeployRegularPresale} from "../script/DeployRegularPresale.s.sol";
import {PriceConverter} from "../src/lib/PriceConverter.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract RegularPresaleTest is Test {
    IERC20 token;
    RegularPresale presale;
    HelperConfig.NetworkConfig config;
    function setUp() public {
        // Deploy Token
        DeployERC20Ownable deployToken = new DeployERC20Ownable();
        token = IERC20(deployToken.run());
        // Deploy Presale
        DeployRegularPresale deployRegularPresale = new DeployRegularPresale();
        HelperConfig helperConfig;
        (presale, helperConfig) = deployRegularPresale.run();
        config = helperConfig.getConfig();
    }

    function testRegularPresale() public {
        uint256 START_TIME = 1e10;
        address feeCollector = address(uint160(vm.envUint("FEE_COLLECTOR")));
        address projectCreator = address(uint160(vm.envUint("PROJECT_CREATOR_ADDRESS")));

        vm.warp(START_TIME);
        uint256 ethToUsd = PriceConverter.getConversionRate(1e18, AggregatorV3Interface(config.priceFeed));
        uint256 usdToEth = 1e18 * 1e18 / ethToUsd;

        vm.startPrank(projectCreator);
        token.approve(address(presale), 100e18);
        presale.createPresale{value: 200*usdToEth}(
            address(token),
            1e18, // price
            100e18, // supply
            START_TIME,
            START_TIME + 1000,
            PoolType.Uniswap  // Uniswap
        );
        console.log("presale created");

        vm.warp(START_TIME + 100);
        presale.joinProjectPresale{value: 5e18}(1);
        console.log("presale joined");
        vm.stopPrank();

        console.log(presale.getTotalTokensOwed(1)/1e18);
        vm.warp(START_TIME + 1001);
        vm.prank(feeCollector);
        presale.endPresale(1);
        console.log("presale ended");

        vm.warp(START_TIME + 1002);
        vm.prank(projectCreator);
        presale.leaveUnsuccessfulProjectPresale(1);
    }

}