// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Check} from "../lib/Check.sol";


enum ProjectStatus {
    Pending,
    Success,
    Failed
}


contract Presale is Ownable, ReentrancyGuard {
    uint256 internal constant DECIMALS = 1e18;
    uint256 internal constant SOFTCAP_PERCENTAGE = 30e16;  // 30%
    address internal s_feeCollector;
    // i_successfulEndFee is a percentage, e.g. 5e16 = 5%.
    // The presale creator and the fee collector get amount raised * i_successfulEndFee / DECIMALS
    uint256 internal immutable i_successfulEndFee;
    address internal immutable i_weth;
    uint256 internal s_lastProjectId; // starts from 1
    mapping (uint256 id => mapping(address contributor => uint256 tokenAmount)) internal s_tokensOwedToContributor;

    constructor(
        address feeCollector,
        address weth,
        uint256 successfulEndFee
    // fee collector is also the owner in the beginning
    ) Ownable(feeCollector) {
        s_feeCollector = feeCollector;
        i_weth = weth;
        i_successfulEndFee = successfulEndFee;
    }

    function withdrawFunds() external onlyOwner {
        require(address(this).balance > 0, "No funds to withdraw");
        payable(s_feeCollector).transfer(address(this).balance);
    }

    function changeFeeCollector(address newFeeCollector) external onlyOwner {
        s_feeCollector = newFeeCollector;
    }

    function sendEther(address payable to, uint256 value) internal {
        // Call returns a boolean value indicating success or failure.
        (bool sent,) = to.call{value: value}("");
        Check.etherTransferSuccess(sent, to, value);
    }
}

