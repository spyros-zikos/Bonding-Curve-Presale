// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BondingCurvePresale, ProjectStatus} from "../src/BondingCurvePresale.sol";
import {DeployBondingCurvePresale} from "../script/DeployBondingCurvePresale.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract BondingCurvePresaleTest is Test {
    BondingCurvePresale presale;
    HelperConfig.NetworkConfig config;

    uint256 START_TIME = 1e5;
    uint256 INVESTOR1_INITIAL_BALANCE = 3e3*1e18;
    uint256 INVESTOR2_INITIAL_BALANCE = 7e3*1e18;
    uint256 INVESTOR3_INITIAL_BALANCE = 32e3*1e18;
    uint256 CREATOR_INITIAL_BALANCE = 6e18;
    uint256 INVESTOR1_ETH_AMOUNT = 2.3e3*1e18; //2
    uint256 INVESTOR2_ETH_AMOUNT = 6.3e3*1e18; //6
    uint256 INVESTOR3_ETH_AMOUNT = 32e3*1e18; //30.7
    uint256 CREATOR_ETH_AMOUNT = 5e18;
    uint256 INVESTOR1_TOKEN_BUY_AMOUNT = 5e7*1e18;
    uint256 INVESTOR2_TOKEN_BUY_AMOUNT = 5e7*1e18;
    uint256 INVESTOR3_TOKEN_BUY_AMOUNT = 12e7*1e18;

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
        vm.deal(investor2, INVESTOR2_INITIAL_BALANCE);
        vm.deal(investor3, INVESTOR3_INITIAL_BALANCE);
        vm.deal(projectCreator, CREATOR_INITIAL_BALANCE);
        vm.warp(START_TIME);
    }

    function testBondingCurvePresaleFailure() public {
        uint256 id = 1; // project i
        
        // Project creator creates presale
        vm.startPrank(projectCreator);
        presale.createPresale{value: CREATOR_ETH_AMOUNT}(
            START_TIME,
            START_TIME + 1000,
            "token name",
            "token symbol"
        );
        console.log("presale created");
        vm.stopPrank();
        IERC20 token = IERC20(presale.getBCPProject(id).token);
        
        console.log("--- investor1 joined presale ---");
        _investorBuysTokens(START_TIME + 100, investor1, INVESTOR1_ETH_AMOUNT, INVESTOR1_TOKEN_BUY_AMOUNT, id, token);
        
        console.log("--- investor2 joined presale ---");
        _investorBuysTokens(START_TIME + 101, investor2, INVESTOR2_ETH_AMOUNT, INVESTOR2_TOKEN_BUY_AMOUNT, id, token);
        
        console.log("getSupply: ", presale.getSupply(id));
        console.log("getSoftCap: ", presale.getSoftCap());


        _feeCollectorEndsPresale(START_TIME + 1001, id);
        console.log("presale fail price: ", presale.getBCPProject(id).priceAfterFailure);

        // // Check if project indeed failed
        // assert(presale.getSupply(id) == INVESTOR1_ETH_AMOUNT + INVESTOR2_ETH_AMOUNT);
        assertEq(uint8(presale.getBCPProject(id).status), uint8(ProjectStatus.Failed), "Presale Not Failed");

        vm.startPrank(investor1);
        // token.approve(address(presale), type(uint256).max);
        vm.warp(START_TIME + 1002);
        presale.leaveUnsuccessfulProjectPresale(id);
        vm.stopPrank();
        console.log("investor1 left failed presale");
        console.log("investor1 balance: ", investor1.balance);

        vm.startPrank(investor2);
        // token.approve(address(presale), type(uint256).max);
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
        presale.createPresale{value: CREATOR_ETH_AMOUNT}(
            START_TIME,
            START_TIME + 1000,
            "token name",
            "token symbol"
        );
        console.log("presale created");
        vm.stopPrank();
        IERC20 token = IERC20(presale.getBCPProject(id).token);

        console.log("--- investor1 joined presale ---");
        _investorBuysTokens(START_TIME + 100, investor1, INVESTOR1_ETH_AMOUNT, INVESTOR1_TOKEN_BUY_AMOUNT, id, token);
        
        console.log("--- investor2 joined presale ---");
        _investorBuysTokens(START_TIME + 101, investor2, INVESTOR2_ETH_AMOUNT, INVESTOR2_TOKEN_BUY_AMOUNT, id, token);
        
        console.log("--- investor3 joined presale ---");
        _investorBuysTokens(START_TIME + 101, investor3, INVESTOR3_ETH_AMOUNT, INVESTOR3_TOKEN_BUY_AMOUNT, id, token);

        // ##################################################
        console.log("--- investor1 leaves presale ---");
        _investorSellsTokens(START_TIME + 101, investor1, INVESTOR1_TOKEN_BUY_AMOUNT/5, id, token);
        // ##################################################

        _feeCollectorEndsPresale(START_TIME + 1001, id);

        // Check if project succeded
        assertEq(uint8(presale.getBCPProject(id).status), uint8(ProjectStatus.Success), "Presale Not Successful");

        // Reverts
        vm.startPrank(investor1);
        // token.approve(address(presale), type(uint256).max);
        vm.warp(START_TIME + 1002);
        vm.expectRevert();
        presale.leaveUnsuccessfulProjectPresale(id);
        vm.stopPrank();

        console.log("Presale balance: ", address(presale).balance);
        uint256 feeCollectorBalanceBeforeWithdraw = feeCollector.balance;
        console.log("Fee collector balance: ", feeCollector.balance - feeCollectorBalanceBeforeWithdraw);
    }


    //////////////////// HELPER FUNCTIONS ////////////////////

    function _investorBuysTokens(uint256 time, address investor, uint256 ethAmount, uint256 tokenAmount, uint256 id, IERC20 token) private {
        vm.warp(time);
        vm.prank(investor);
        presale.buyTokens{value: ethAmount}(id, tokenAmount, 0);
        console.log("total tokens owed: ", presale.getSupply(id));
        console.log("investor token balance: ", token.balanceOf(investor));
        console.log("price: ", presale.priceToChangeTokenSupply(presale.getSupply(id), presale.getSupply(id) + 1e18));
    }

    function _investorSellsTokens(uint256 time, address investor, uint256 tokenAmount, uint256 id, IERC20 token) private {
        vm.warp(time);
        // vm.prank(investor);
        // token.approve(address(presale), type(uint256).max);
        vm.prank(investor);
        presale.sellTokens(id, tokenAmount, 0);
        console.log("total tokens owed: ", presale.getSupply(id));
        console.log("investor token balance: ", token.balanceOf(investor));
        console.log("investor eth balance: ", investor.balance);
        console.log("price: ", presale.priceToChangeTokenSupply(presale.getSupply(id), presale.getSupply(id) + 1e18));
    }

    function _feeCollectorEndsPresale(uint256 time, uint256 id) private {
        // Fee collector ends presale
        vm.warp(time);
        vm.prank(feeCollector);
        presale.endPresale(id);
        console.log("presale ended");
    }
}