// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BondingCurvePresale, PoolType, ProjectStatus} from "../src/BondingCurvePresale.sol";
import {DeployBondingCurvePresale} from "../script/DeployBondingCurvePresale.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract BondingCurvePresaleTest is Test {
    BondingCurvePresale presale;
    HelperConfig.NetworkConfig config;

    uint256 START_TIME = 1e5;
    uint256 INVESTOR1_INITIAL_BALANCE = 0.01e18;
    uint256 INVESTOR2_INITIAL_BALANCE = 0.01e18;
    uint256 INVESTOR3_INITIAL_BALANCE = 0.5e18;
    uint256 INVESTOR1_JOIN_AMOUNT = 0.01e18;
    uint256 INVESTOR2_JOIN_AMOUNT = 0.01e18;
    uint256 INVESTOR3_JOIN_AMOUNT = 0.5e18;
    uint256 PRICE_PER_TOKEN = 1e18;
    uint256 INITIAL_SUPPLY = 100e18;

    address feeCollector = address(uint160(vm.envUint("FEE_COLLECTOR")));
    address projectCreator = address(uint160(vm.envUint("PROJECT_CREATOR_ADDRESS")));
    address investor1 = makeAddr("investor1");
    address investor2 = makeAddr("investor2");
    address investor3 = makeAddr("investor3");

    function setUp() public {
        // Deploy Presale
        DeployBondingCurvePresale deployBondingCurvePresale = new DeployBondingCurvePresale();
        HelperConfig helperConfig;
        (presale, helperConfig) = deployBondingCurvePresale.run();
        config = helperConfig.getConfig();

        vm.deal(investor1, INVESTOR1_INITIAL_BALANCE);
        vm.deal(investor3, INVESTOR3_INITIAL_BALANCE);
        vm.deal(investor2, INVESTOR2_INITIAL_BALANCE);
        vm.warp(START_TIME);
    }

    function testBondingCurvePresaleFailure() public {
        uint256 id = 1; // project id
        
        // Project creator creates presale
        vm.startPrank(projectCreator);
        presale.createPresale(
            INITIAL_SUPPLY, // initial supply/amount
            START_TIME,
            START_TIME + 1000,
            PoolType.Uniswap,  // Uniswap
            "token name",
            "token symbol"
        );
        console.log("presale created");
        vm.stopPrank();
        IERC20 token = IERC20(presale.getBCPProject(id).token);
        
        console.log("--- investor1 joined presale ---");
        _investorJoinsPresale(START_TIME + 100, investor1, INVESTOR1_JOIN_AMOUNT, id, token);
        
        console.log("--- investor2 joined presale ---");
        _investorJoinsPresale(START_TIME + 101, investor2, INVESTOR2_JOIN_AMOUNT, id, token);

        _feeCollectorEndsPresale(START_TIME + 1001, id);
        console.log("presale fail price: ", presale.getBCPProject(id).priceAfterFailure);

        // // Check if project indeed failed
        // assert(presale.getTotalTokensOwed(id) == INVESTOR1_JOIN_AMOUNT + INVESTOR2_JOIN_AMOUNT);
        // assert(presale.getSoftCap(id) == (INITIAL_SUPPLY / 2) * 3 / 10);
        assert(presale.getBCPProject(id).status == ProjectStatus.Failed);

        uint256 investor1EthBalanceBeforeExit = investor1.balance;
        assert(investor1EthBalanceBeforeExit == 0);
        vm.startPrank(investor1);
        token.approve(address(presale), type(uint256).max);
        vm.warp(START_TIME + 1002);
        presale.leaveUnsuccessfulProjectPresale(id);
        vm.stopPrank();
        console.log("investor1 left failed presale");
        console.log("investor1 balance: ", investor1.balance);

        uint256 investor2EthBalanceBeforeExit = investor2.balance;
        assert(investor2EthBalanceBeforeExit == 0);
        vm.startPrank(investor2);
        token.approve(address(presale), type(uint256).max);
        vm.warp(START_TIME + 1003);
        presale.leaveUnsuccessfulProjectPresale(id);
        vm.stopPrank();
        console.log("investor2 left failed presale");
        console.log("investor2 balance: ", investor2.balance);
    }

    function testBondingCurvePresaleSuccess() public {
        uint256 id = 1; // project id

        // Project creator creates presale
        vm.startPrank(projectCreator);
        presale.createPresale(
            INITIAL_SUPPLY, // initial supply/amount
            START_TIME,
            START_TIME + 1000,
            PoolType.Balancer, 
            "token name",
            "token symbol"
        );
        console.log("presale created");
        vm.stopPrank();
        IERC20 token = IERC20(presale.getBCPProject(id).token);

        console.log("--- investor1 joined presale ---");
        _investorJoinsPresale(START_TIME + 100, investor1, INVESTOR1_JOIN_AMOUNT, id, token);
        
        console.log("--- investor2 joined presale ---");
        _investorJoinsPresale(START_TIME + 101, investor2, INVESTOR2_JOIN_AMOUNT, id, token);
        
        console.log("--- investor3 joined presale ---");
        _investorJoinsPresale(START_TIME + 101, investor3, INVESTOR3_JOIN_AMOUNT, id, token);

        // ##################################################
        console.log("--- investor1 leaves presale ---");
        _investorLeavesPresale(START_TIME + 101, investor1, token.balanceOf(investor1), id, token);
        // ##################################################

        // vm.prank(projectCreator);
        // IERC20(presale.getBCPProject(id).token).approve(address(config.CPFactory), type(uint256).max);
        _feeCollectorEndsPresale(START_TIME + 1001, id);

        // Check if project succeded
        assert(presale.getBCPProject(id).status == ProjectStatus.Success);

        // // Reverts
        vm.startPrank(investor1);
        token.approve(address(presale), type(uint256).max);
        vm.warp(START_TIME + 1002);
        vm.expectRevert();
        presale.leaveUnsuccessfulProjectPresale(id);
        vm.stopPrank();

        console.log("Presale balance: ", address(presale).balance);
        uint256 feeCollectorBalanceBeforeWithdraw = feeCollector.balance;
        vm.prank(feeCollector);
        presale.withdrawFunds();
        console.log("Presale balance after withdraw: ", address(presale).balance);
        console.log("Fee collector balance increase after withdraw: ", feeCollector.balance - feeCollectorBalanceBeforeWithdraw);
    }


    //////////////////// HELPER FUNCTIONS ////////////////////

    function _investorJoinsPresale(uint256 time, address investor, uint256 amount, uint256 id, IERC20 token) private {
        vm.warp(time);
        vm.prank(investor);
        presale.joinProjectPresale{value: amount}(id, 0);
        console.log("total tokens owed: ", presale.getTotalTokensOwed(id));
        console.log("investor token balance: ", token.balanceOf(investor));
        console.log("price: ", presale.calculatePrice(presale.getTotalTokensOwed(id)));
    }

    function _investorLeavesPresale(uint256 time, address investor, uint256 amount, uint256 id, IERC20 token) private {
        vm.warp(time);
        vm.prank(investor);
        token.approve(address(presale), type(uint256).max);
        vm.prank(investor);
        presale.leaveOngoingProjectPresale(id, amount, 0);
        console.log("total tokens owed: ", presale.getTotalTokensOwed(id));
        console.log("investor token balance: ", token.balanceOf(investor));
        console.log("investor eth balance: ", investor.balance);
        console.log("price: ", presale.calculatePrice(presale.getTotalTokensOwed(id)));
    }

    function _feeCollectorEndsPresale(uint256 time, uint256 id) private {
        // Fee collector ends presale
        vm.warp(time);
        vm.prank(feeCollector);
        presale.endPresale(id);
        console.log("presale ended");
    }
}