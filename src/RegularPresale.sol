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
    uint256 startTime,
    uint256 endTime
);
event UserJoinedProject(uint256 id, address contributor, uint256 tokenAmount);
event UserLeftProject(uint256 id, address contributor, uint256 etherToGiveBack);


// Create presale errors
error InvalidTokenAddress(address token);
error InvalidTokenPrice(uint256 tokenPrice);
error StartTimeMustBeInFuture(uint256 startTime, uint256 currentTime);
error EndTimeMustBeAfterStartTime(uint256 startTime, uint256 endTime);
error IncorrectCreationFee(uint256 feePaid, uint256 actualFee);
error InitialTokenAmountMustBeEven(uint256 initialTokenAmount);
// Join presale errors
error InvalidProjectId(uint256 id);
error ProjectIsNotPending(uint256 id);
error ProjectHasNotStarted(uint256 id);
error ProjectHasEnded(uint256 id);
error NoMoreTokensToGive(uint256 id);
// Leave presale errors
error ProjectHasNotFailed(uint256 id);
error UserHasNotContributed(uint256 id, address contributor);
// End presale errors
error ProjectHasNotEnded(uint256 id);
// Other
error EtherTransferFailed(address to, uint256 value);

enum ProjectStatus {
    Pending,
    Success,
    Failed
}

struct Project {
    address token;
    uint256 price; // in USD, 18 decimals
    uint256 initialTokenAmount;
    uint256 raised; // in ETH
    uint256 startTime;
    uint256 endTime;
    address creator;
    address[] contributors;
    ProjectStatus status;
}

contract RegularPresale is Ownable, ReentrancyGuard {
    uint256 constant DECIMALS = 1e18;
    uint256 private s_creationFee;
    uint256 private s_successfulEndFee; // percentage, e.g. 10e16 = 10%
    address private s_feeCollector;
    AggregatorV3Interface private s_priceFeed;
    uint256 private s_lastProjectId; // starts from 1
    mapping (uint256 id => Project project) private s_projectFromId;
    mapping (uint256 id => mapping(address contributor => uint256 tokenAmount)) s_tokensOwedToContributor;

    modifier validId(uint256 _id) {
        // Check if project id is valid
        if (_id > s_lastProjectId || _id <= 0) {
            revert InvalidProjectId(_id);
        }
        _;
    }

    constructor(uint256 _creationFee, uint256 _successfulEndFee, address _feeCollector, address _priceFeed) Ownable(msg.sender) {
        s_creationFee = _creationFee;
        s_successfulEndFee = _successfulEndFee;
        s_feeCollector = _feeCollector;
        s_priceFeed = AggregatorV3Interface(_priceFeed);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function createPresale(
        address _token,
        uint256 _tokenPrice,
        uint256 _initialTokenAmount, // must be even so that half goes to presale and half to pool
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
        ////////////////////////////////////////
        // Actions /////////////////////////////
        ////////////////////////////////////////
        // Transfer initial token amount from user to this contract
        IERC20(_token).transferFrom(msg.sender, address(this), _initialTokenAmount);
        s_lastProjectId += 1;
        address[] memory _contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: _token,
            price: _tokenPrice,
            initialTokenAmount: _initialTokenAmount,
            raised: 0,
            startTime: _startTime,
            endTime: _endTime,
            creator: msg.sender,
            contributors: _contributors,
            status: ProjectStatus.Pending
        });
        emit ProjectCreated(s_lastProjectId, _token, _tokenPrice, _initialTokenAmount, _startTime, _endTime);
    }

    function joinProjectPresale(uint256 _id) external payable nonReentrant validId(_id) {
        ////////////////////////////////////////
        // Checks //////////////////////////////
        ////////////////////////////////////////
        // Check if the project is pending
        if (s_projectFromId[_id].status != ProjectStatus.Pending) {
            revert ProjectIsNotPending(_id);
        }
        // Check if the project is upcoming
        if (s_projectFromId[_id].startTime > block.timestamp) {
            revert ProjectHasNotStarted(_id);
        }
        // Check if the project has ended
        if (projectHasEnded(_id)) {
            revert ProjectHasEnded(_id);
        }
        // If no more tokens to give revert
        if (getRemainingTokens(_id) == 0) {
            revert NoMoreTokensToGive(_id);
        }
        ////////////////////////////////////////
        // Actions /////////////////////////////
        ////////////////////////////////////////
        uint256 tokenAmount = msg.value * DECIMALS / s_projectFromId[_id].price;
        // Check if contributions surpass max presale token amount, then give only what is left
        if (IERC20(s_projectFromId[_id].token).balanceOf(address(this)) + tokenAmount > getMaxPresaleTokenAmount(_id)) {
            tokenAmount = getRemainingTokens(_id);
        }
        // Add contributor to project
        if (!contributorExists(_id, msg.sender)) {
            s_projectFromId[_id].contributors.push(msg.sender);
        }
        s_tokensOwedToContributor[_id][msg.sender] += tokenAmount;
        s_projectFromId[_id].raised += msg.value;
        emit UserJoinedProject(_id, msg.sender, tokenAmount);
    }

    // Needs the user to approve the token transfer before calling this function
    function leaveAfterUnsuccessfulPresale(uint256 _id) external payable nonReentrant validId(_id) {
        // Check if the project has failed
        if (s_projectFromId[_id].status != ProjectStatus.Failed) {
            revert ProjectHasNotFailed(_id);
        }
        // Check if user has contributed
        if (!contributorExists(_id, msg.sender)) {
            revert UserHasNotContributed(_id, msg.sender);
        }

        // Calculate ether to give back
        uint256 etherToGiveBack = s_tokensOwedToContributor[_id][msg.sender] * s_projectFromId[_id].price / DECIMALS;
        // Reset tokens owed to user
        s_tokensOwedToContributor[_id][msg.sender] = 0;
        // give it back
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftProject(_id, msg.sender, etherToGiveBack);
    }

    function endPresale(uint256 _id) external nonReentrant validId(_id) {
        // Check if the project is pending
        if (s_projectFromId[_id].status != ProjectStatus.Pending) {
            revert ProjectIsNotPending(_id);
        }

        if (projectHasEnded(_id)) {
            if (projectSuccessful(_id)) {
                s_projectFromId[_id].status = ProjectStatus.Success;
            } else {
                s_projectFromId[_id].status = ProjectStatus.Failed;
            }
        } else {
            revert ProjectHasNotEnded(_id);
        }

        if (projectSuccessful(_id)) {
            
            // TODO: distribute tokens to contributors
            for (uint256 i = 0; i < s_projectFromId[_id].contributors.length; i++) {
                address contributor = s_projectFromId[_id].contributors[i];
                uint256 tokensToGive = s_tokensOwedToContributor[_id][contributor];
                IERC20(s_projectFromId[_id].token).transfer(contributor, tokensToGive);
                s_tokensOwedToContributor[_id][contributor] = 0; // that's probably not needed
            }
            // Calculate successful-end fee ether amount
            uint256 successfulEndFeeAmount = s_projectFromId[_id].raised * s_successfulEndFee / 1e18;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[_id].creator), successfulEndFeeAmount);
            // Reduce amount raised by 2*successfulEndFeeAmount
            // so that successfulEndFeeAmount is sent to creator
            // and successfulEndFeeAmount remains in the contract for the fee collector to collct
            uint256 amountRaisedAfterFees = s_projectFromId[_id].raised - (2 * successfulEndFeeAmount);
            // TODO: send tokens to pool

        }
    }

    function withdrawFunds() external onlyOwner {
        require(address(this).balance > 0, "No funds to withdraw");
        payable(s_feeCollector).transfer(address(this).balance);
    }

    ////////////////////////////////////////
    // Helpers /////////////////////////////
    ////////////////////////////////////////

    function getSoftCap(uint256 _id) public view returns (uint256) {
        return getMaxPresaleTokenAmount(s_projectFromId[_id].initialTokenAmount) * 3 / 10;
    }

    function getTotalTokensOwed(uint256 _id) public view returns (uint256) {
        uint256 totalTokensOwed = 0;
        for (uint256 i = 0; i < s_projectFromId[_id].contributors.length; i++) {
            totalTokensOwed += s_tokensOwedToContributor[_id][s_projectFromId[_id].contributors[i]];
        }
        return totalTokensOwed;
    }

    function getRemainingTokens(uint256 _id) public view returns (uint256) {
        // tokens that have been distributed
        uint256 distributedTokens = s_projectFromId[_id].initialTokenAmount - IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        // max tokens that can be distributed
        uint256 maxTokensToBeDistributed = getMaxPresaleTokenAmount(_id);
        // tokens that can be distributed
        uint256 remainingTokens = maxTokensToBeDistributed - distributedTokens;
        return remainingTokens;
    }

    function contributorExists(uint256 _id, address _contributor) public view returns (bool) {
        for (uint256 i = 0; i < s_projectFromId[_id].contributors.length; i++) {
            if (s_projectFromId[_id].contributors[i] == _contributor) {
                return true;
            }
        }
        return false;
    }

    function getMaxPresaleTokenAmount(uint256 _id) public view returns (uint256) {
        return s_projectFromId[_id].initialTokenAmount / 2;
    }

    function sendEther(address payable _to, uint256 _value) private {
        // Call returns a boolean value indicating success or failure.
        (bool sent,) = _to.call{value: _value}("");
        if (!sent) {
            revert EtherTransferFailed(_to, _value);
        }
    }

    function projectHasEnded(uint256 _id) public view returns (bool) {
        return s_projectFromId[_id].endTime < block.timestamp;
    }

    function projectSuccessful(uint256 _id) public view returns (bool) {
        return getTotalTokensOwed(_id) >= getSoftCap(_id);
    }

    // TODO get stats functions

    // Future: check fees in range
}