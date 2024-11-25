// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

event ProjectCreated(
    uint256 lastProjectId,
    address token,
    uint256 tokenPrice, 
    uint256 initialTokenAmount, 
    uint256 hardCap, 
    uint256 startTime, 
    uint256 endTime
);
event ProjectJoined(uint256 id, address contributor, uint256 tokenAmount);

// Create presale errors
error InvalidTokenAddress(address token);
error InvalidTokenPrice(uint256 tokenPrice);
error StartTimeMustBeInFuture(uint256 startTime, uint256 currentTime);
error EndTimeMustBeAfterStartTime(uint256 startTime, uint256 endTime);
error IncorrectCreationFee(uint256 feePaid, uint256 actualFee);
error InitialTokenAmountMustBeEven(uint256 initialTokenAmount);
error IncorrectHardCap(uint256 hardCap, uint256 maxPresaleTokenAmount);
// Join presale errors
error InvalidProjectId(uint256 id);
error ProjectIsNotPending(uint256 id);
error ProjectHasNotStarted(uint256 id);
error ProjectHasEnded(uint256 id);
error HardCapSurpassed(uint256 tokenAmount, uint256 hardCap);

enum ProjectStatus {
    Pending,
    Completed,
    Failed
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
    ProjectStatus status;
}

contract RegularPresale is Ownable, ReentrancyGuard {
    uint256 private s_creationFee;
    address private s_feeCollector;
    AggregatorV3Interface private s_priceFeed;
    uint256 private s_lastProjectId; // starts from 1
    mapping (uint256 id => Project project) private s_projectFromId;
    mapping (uint256 id => mapping(address contributor => uint256 tokenAmount)) s_contributions;

    constructor(uint256 _creationFee, address _feeCollector, address _priceFeed) Ownable(msg.sender) {
        s_creationFee = _creationFee;
        s_feeCollector = _feeCollector;
        s_priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function createPresale(
        address _token,
        uint256 _tokenPrice,
        uint256 _initialTokenAmount, // must be even so that half goes to presale and half to pool
        uint256 _hardCap, // in tokens, has to be <= initialTokenAmount / 2
        uint256 _startTime,
        uint256 _endTime
    ) external payable nonReentrant {  // probably does not need nonReentrant but just in case
        ////////////////////////////////////////
        // Checks //////////////////////////////
        ////////////////////////////////////////
        // Check if token address is valid
        if (_token == address(0)) {
            revert InvalidTokenAddress(_token);
        }
        // Check if token price is greater than 0
        if (_tokenPrice <= 0) {
            revert InvalidTokenPrice(_tokenPrice);
        }
        // Check if startTime is in the future
        if (block.timestamp > _startTime) {
            revert StartTimeMustBeInFuture(_startTime, block.timestamp);
        }
        // Check if endTime is after startTime
        if (_endTime <= _startTime) {
            revert EndTimeMustBeAfterStartTime(_startTime, _endTime);
        }
        // Calculate fee paid
        uint256 msgValueInUsd = PriceConverter.getConversionRate(msg.value, s_priceFeed);
        // Check if the fee paid is correct
        if (msgValueInUsd != s_creationFee) {
            revert IncorrectCreationFee(msgValueInUsd, s_creationFee);
        }
        // Check if initial token amount is an even number
        if (_initialTokenAmount % 2 != 0) {
            revert InitialTokenAmountMustBeEven(_initialTokenAmount);
        }
        // Check if hard cap is correct
        if (_hardCap > getMaxPresaleTokenAmount(_initialTokenAmount)) {
            revert IncorrectHardCap(_hardCap, getMaxPresaleTokenAmount(_initialTokenAmount));
        }

        ////////////////////////////////////////
        // Actions /////////////////////////////
        ////////////////////////////////////////
        // Take initial token amount from user to this contract
        IERC20(_token).transferFrom(msg.sender, address(this), _initialTokenAmount);

        s_lastProjectId += 1;
        address[] memory _contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: _token,
            price: _tokenPrice,
            initialTokenAmount: _initialTokenAmount,
            raised: 0,
            hardCap: _hardCap,
            startTime: _startTime,
            endTime: _endTime,
            contributors: _contributors,
            status: ProjectStatus.Pending
        });
        emit ProjectCreated(s_lastProjectId, _token, _tokenPrice, _initialTokenAmount, _hardCap, _startTime, _endTime);
    }

    function joinProjectPresale(uint256 _id) external payable nonReentrant {
        ////////////////////////////////////////
        // Checks //////////////////////////////
        ////////////////////////////////////////
        // Check if project id is valid
        if (_id > s_lastProjectId || _id <= 0) {
            revert InvalidProjectId(_id);
        }
        // Check if the project is pending
        if (s_projectFromId[_id].status != ProjectStatus.Pending) {
            revert ProjectIsNotPending(_id);
        }
        // Check if the project is upcoming
        if (s_projectFromId[_id].startTime > block.timestamp) {
            revert ProjectHasNotStarted(_id);
        }
        // Check if the project has ended
        if (s_projectFromId[_id].endTime < block.timestamp) {
            revert ProjectHasEnded(_id);
        }
        uint256 tokenAmount = (msg.value * 1e18 / s_projectFromId[_id].price);
        // Check if contributions surpass hardcap
        if (tokenAmount > s_projectFromId[_id].hardCap) {
            revert HardCapSurpassed(tokenAmount, s_projectFromId[_id].hardCap);
        }

        ////////////////////////////////////////
        // Actions /////////////////////////////
        ////////////////////////////////////////
        // Add contributor to project
        if (!contributorExists(_id, msg.sender)) {
            s_projectFromId[_id].contributors.push(msg.sender);
        }
        s_contributions[_id][msg.sender] += tokenAmount;
        // Send tokens to contributor
        IERC20(s_projectFromId[_id].token).transfer(msg.sender, tokenAmount);
        emit ProjectJoined(_id, msg.sender, tokenAmount);
    }

    function leaveAfterUnsuccessfulPresale() external {
        // TODO
    }

    function endPresale() external {
        // TODO
    }

    function withdrawFunds() external onlyOwner {
        require(address(this).balance > 0, "No funds to withdraw");
        payable(s_feeCollector).transfer(address(this).balance);
    }

    function getSoftCap(uint256 _id) external view returns (uint256) {
        return s_projectFromId[_id].hardCap * 3 / 10;
    }

    function contributorExists(uint256 _id, address _contributor) public view returns (bool) {
        for (uint256 i = 0; i < s_projectFromId[_id].contributors.length; i++) {
            if (s_projectFromId[_id].contributors[i] == _contributor) {
                return true;
            }
        }
        return false;
    }

    function getMaxPresaleTokenAmount(uint256 _initialTokenAmount) public pure returns (uint256) {
        return _initialTokenAmount / 2;
    }

    // TODO get stats functions
}