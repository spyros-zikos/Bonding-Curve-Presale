// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

struct Project {
    address token;
    uint256 price;
    uint256 initialTokenAmount;
    uint256 raised;
    uint256 hardCap;
    uint256 startDate;
    uint256 endDate;
    address[] contributors;
}

contract RegularPresale is Ownable {
    uint256 private s_lastProjectId;
    mapping (uint256 id => Project project) private s_projectFromId;

    constructor() Ownable(msg.sender) {}

    function createPresale(address _token, uint256 _price,  uint256 _initialTokenAmount,uint256 _hardCap, uint256 _startDate, uint256 _endDate) external payable {

        // TODO PAY FEE to owner of this contract

        s_lastProjectId += 1;

        address[] memory _contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: _token,
            price: _price,
            initialTokenAmount: _initialTokenAmount,
            raised: 0,
            hardCap: _hardCap,
            startDate: _startDate,
            endDate: _endDate,
            contributors: _contributors
        });
    }

    function joinPresale() external {
        // TODO
    }

    function leavePresale() external {
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
        payable(owner()).transfer(address(this).balance);
    }

    // TODO get stats functions
}