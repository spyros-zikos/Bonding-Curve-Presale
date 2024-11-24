// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


error StartTimeMustBeInFuture(uint256 startTime, uint256 currentTime);
error CreationFeeNotCorrect(uint256 feePaid, uint256 actualFee);

enum ProjectState {
    Upcoming,
    Live,
    EndedSuccessfully,
    EndedUnsuccessfully
}

struct Project {
    address token;
    uint256 price; // in USD, 18 decimals
    uint256 initialTokenAmount;
    uint256 raised;
    uint256 hardCap;
    uint256 startTime;
    uint256 endTime;
    address[] contributors;
    ProjectState state;
}

contract RegularPresale is Ownable {
    uint256 creationFee;
    address feeCollector;
    uint256 private s_lastProjectId; // starts from 1
    mapping (uint256 id => Project project) private s_projectFromId;

    constructor(uint256 _creationFee, address _feeCollector) Ownable(msg.sender) {
        creationFee = _creationFee;
        feeCollector = _feeCollector;
    }

    function createPresale(
        address _token,
        uint256 _price,
        uint256 _initialTokenAmount,
        uint256 _hardCap,
        uint256 _startTime,
        uint256 _endTime
    ) external payable {
        // Check if startTime is in the future
        if (block.timestamp > _startTime) {
            revert StartTimeMustBeInFuture(_startTime, block.timestamp);
        }
        // TODO calculate creation fee
        // uint256 creationFeeInUsd = getEthPrice() * creationFee / 10**18;
        
        // Check if the creation fee is correct
        if (msg.value == creationFee) {
            revert CreationFeeNotCorrect(msg.value, creationFee);
        }

        // TODO Pay fee to fee collector

        s_lastProjectId += 1;
        address[] memory _contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: _token,
            price: _price,
            initialTokenAmount: _initialTokenAmount,
            raised: 0,
            hardCap: _hardCap,
            startTime: _startTime,
            endTime: _endTime,
            contributors: _contributors,
            state: ProjectState.Upcoming
        });
    }

    function joinPresale() external {
        // TODO
    }

    function leaveAfterUnsuccessfulPresale() external {
        // TODO
    }

    function endPresale() external {
        // TODO
    }

    function getSoftCap(uint256 id) external view returns (uint256) {
        return s_projectFromId[id].hardCap * 3 / 10;
    }

    function withdrawFunds() external onlyOwner {
        require(address(this).balance > 0, "No funds to withdraw");
        payable(feeCollector).transfer(address(this).balance);
    }

    // TODO get stats functions
}