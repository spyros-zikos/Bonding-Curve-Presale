// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployERC20Ownable} from "../script/DeployERC20Ownable.s.sol";
import {RegularPresale, PoolType, ProjectStatus} from "../src/RegularPresale.sol";
import {DeployRegularPresale} from "../script/DeployRegularPresale.s.sol";
import {PriceConverter} from "../src/lib/PriceConverter.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract RegularPresaleTest is Test {
    IERC20 token;
    RegularPresale presale;
    HelperConfig.NetworkConfig config;

    uint256 START_TIME = 1e5;
    uint256 INVESTOR1_INITIAL_BALANCE = 5e18;
    uint256 INVESTOR2_INITIAL_BALANCE = 5e18;
    uint256 INVESTOR3_INITIAL_BALANCE = 20e18;
    uint256 INVESTOR1_JOIN_AMOUNT = 5e18;
    uint256 INVESTOR2_JOIN_AMOUNT = 5e18;
    uint256 INVESTOR3_JOIN_AMOUNT = 20e18;
    uint256 PRICE_PER_TOKEN = 1e18;
    uint256 INITIAL_SUPPLY = 100e18;

    address feeCollector = address(uint160(vm.envUint("FEE_COLLECTOR")));
    address projectCreator = address(uint160(vm.envUint("PROJECT_CREATOR_ADDRESS")));
    address investor1 = makeAddr("investor1");
    address investor2 = makeAddr("investor2");
    address investor3 = makeAddr("investor3");

    function setUp() public {
        // Deploy Token
        DeployERC20Ownable deployToken = new DeployERC20Ownable();
        token = IERC20(deployToken.run());
        // Deploy Presale
        DeployRegularPresale deployRegularPresale = new DeployRegularPresale();
        HelperConfig helperConfig;
        (presale, helperConfig) = deployRegularPresale.run();
        config = helperConfig.getConfig();

        vm.deal(investor1, INVESTOR1_INITIAL_BALANCE);
        vm.deal(investor2, INVESTOR2_INITIAL_BALANCE);
        vm.deal(investor3, INVESTOR3_INITIAL_BALANCE);
        vm.warp(START_TIME);
    }

    function testRegularPresaleFailure() public {
        uint256 id = 1; // project id
        
        uint256 ethToUsd = PriceConverter.getConversionRate(1e18, AggregatorV3Interface(config.priceFeed));
        uint256 usdToEth = 1e18 * 1e18 / ethToUsd;

        // Project creator creates presale
        vm.startPrank(projectCreator);
        token.approve(address(presale), INITIAL_SUPPLY);
        presale.createPresale{value: 200*usdToEth}(
            address(token),
            PRICE_PER_TOKEN,
            INITIAL_SUPPLY, // supply
            START_TIME,
            START_TIME + 1000,
            PoolType.Uniswap  // Uniswap
        );
        console.log("presale created");
        vm.stopPrank();

        _investorJoinsPresale(START_TIME + 100, investor1, INVESTOR1_JOIN_AMOUNT, id);
        _investorJoinsPresale(START_TIME + 101, investor2, INVESTOR2_JOIN_AMOUNT, id);

        _feeCollectorEndsPresale(START_TIME + 1001, id);

        // Check if project indeed failed
        assert(presale.getTotalTokensOwed(id) == INVESTOR1_JOIN_AMOUNT + INVESTOR2_JOIN_AMOUNT);
        assert(presale.getSoftCap(id) == (INITIAL_SUPPLY / 2) * 3 / 10);
        assert(presale.getProject(id).status == ProjectStatus.Failed);

        uint256 investor1EthBalanceBeforeExit = investor1.balance;
        assert(investor1EthBalanceBeforeExit == 0);
        vm.warp(START_TIME + 1002);
        vm.prank(investor1);
        presale.leaveUnsuccessfulProjectPresale(id);
        console.log("investor1 left failed presale");
        // Check if investor1 gets back his money after failed project
        assert(investor1.balance == investor1EthBalanceBeforeExit + 5e18);

        uint256 investor2EthBalanceBeforeExit = investor2.balance;
        assert(investor2EthBalanceBeforeExit == 0);
        vm.warp(START_TIME + 1002);
        vm.prank(investor2);
        presale.leaveUnsuccessfulProjectPresale(id);
        console.log("investor2 left failed presale");
        // Check if investor2 gets back his money after failed project
        assert(investor2.balance == investor2EthBalanceBeforeExit + 5e18);
    }

    function testRegularPresaleSuccess() public {
        uint256 id = 1; // project id
        
        uint256 ethToUsd = PriceConverter.getConversionRate(1e18, AggregatorV3Interface(config.priceFeed));
        uint256 usdToEth = 1e18 * 1e18 / ethToUsd;

        // Project creator creates presale
        vm.startPrank(projectCreator);
        token.approve(address(presale), INITIAL_SUPPLY);
        presale.createPresale{value: 200*usdToEth}(
            address(token),
            PRICE_PER_TOKEN,
            INITIAL_SUPPLY,
            START_TIME,
            START_TIME + 1000,
            PoolType.Uniswap
        );
        console.log("presale created");
        vm.stopPrank();

        _investorJoinsPresale(START_TIME + 100, investor1, INVESTOR1_JOIN_AMOUNT, id);
        _investorJoinsPresale(START_TIME + 101, investor2, INVESTOR2_JOIN_AMOUNT, id);
        _investorJoinsPresale(START_TIME + 102, investor3, INVESTOR3_JOIN_AMOUNT, id);

        _feeCollectorEndsPresale(START_TIME + 1001, id);

        // Check if project succeded
        assert(presale.getTotalTokensOwed(id) == INVESTOR1_JOIN_AMOUNT + INVESTOR2_JOIN_AMOUNT + INVESTOR3_JOIN_AMOUNT);
        assert(presale.getSoftCap(id) == (INITIAL_SUPPLY / 2) * 3 / 10);
        assert(presale.getProject(id).status == ProjectStatus.Success);

        // Reverts
        vm.warp(START_TIME + 1002);
        vm.expectRevert();
        vm.prank(investor1);
        presale.leaveUnsuccessfulProjectPresale(id);

        console.log("Presale balance: ", address(presale).balance);
    }


    //////////////////// HELPER FUNCTIONS ////////////////////

    function _investorJoinsPresale(uint256 time, address investor, uint256 amount, uint256 id) private {
        // Investor1 joins presale
        vm.warp(time);
        vm.prank(investor);
        presale.joinProjectPresale{value: amount}(id);
        console.log("investor joined presale");
        console.log("tokens owed: ", presale.getTotalTokensOwed(id)/1e18);
    }

    function _feeCollectorEndsPresale(uint256 time, uint256 id) private {
        // Fee collector ends presale
        vm.warp(time);
        vm.prank(feeCollector);
        presale.endPresale(id);
        console.log("presale ended");
    }
}