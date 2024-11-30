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
    // percentage, e.g. 5e16 = 5% - the presale creator an the fee collector get amount raised * s_successfulEndFee / DECIMALS
    uint256 internal s_successfulEndFee;
    address internal s_weth;
    uint256 internal s_lastProjectId; // starts from 1

    constructor(
        address _feeCollector,
        address _weth,
        uint256 _successfulEndFee
    // fee collector is also the owner
    ) Ownable(_feeCollector) {
        s_feeCollector = _feeCollector;
        s_weth = _weth;
        s_successfulEndFee = _successfulEndFee;
    }

    function withdrawFunds() external onlyOwner {
        require(address(this).balance > 0, "No funds to withdraw");
        payable(s_feeCollector).transfer(address(this).balance);
    }

    function sendEther(address payable _to, uint256 _value) internal {
        // Call returns a boolean value indicating success or failure.
        (bool sent,) = _to.call{value: _value}("");
        Check.etherTransferSuccess(sent, _to, _value);
    }
}

