// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Check} from "../lib/Check.sol";
import {console} from "forge-std/console.sol";

enum ProjectStatus {
    Pending,
    Success,
    Failed
}


contract Presale is Ownable, ReentrancyGuard {
    uint256 internal constant DECIMALS = 1e18;
    address internal immutable i_weth;
    // i_successfulEndFee is a percentage, e.g. 5e16 = 5%.
    // The presale creator and the fee collector get amount raised * i_successfulEndFee / DECIMALS
    uint256 internal immutable i_successfulEndFee;
    uint256 internal s_softcapPercentage = 30e16;  // 30%
    address internal s_feeCollector;
    uint256 internal s_lastProjectId; // starts from 1

    constructor(
        address feeCollector,
        address weth,
        uint256 successfulEndFee
    // fee collector is also the owner in the beginning
    ) Ownable(msg.sender) {
        s_feeCollector = feeCollector;
        i_weth = weth;
        i_successfulEndFee = successfulEndFee;
    }

    function changeFeeCollector(address newFeeCollector) external onlyOwner {
        s_feeCollector = newFeeCollector;
    }

    function sendEther(address payable to, uint256 value) internal {
        // Call returns a boolean value indicating success or failure.
        (bool sent,) = to.call{value: value}("");
        Check.etherTransferSuccess(sent, to, value);
    }

    function setSoftcapPercentage(uint256 softcapPercentage) external onlyOwner {
        s_softcapPercentage = softcapPercentage;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getWeth() external view returns (address) {
        return i_weth;
    }

    function getSuccessfulEndFee() external view returns (uint256) {
        return i_successfulEndFee;
    }

    function getSoftcapPercentage() external view returns (uint256) {
        return s_softcapPercentage;
    }

    function getFeeCollector() external view returns (address) {
        return s_feeCollector;
    }

    function getLastProjectId() external view returns (uint256) {
        return s_lastProjectId;
    }
}

