// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


import {ProjectStatus} from "./Presale.sol";
import {PoolType} from "./PoolDeployer.sol";
import {Check} from "../lib/Check.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Presale, ProjectStatus} from "../utils/Presale.sol";


event ProjectStatusUpdated(uint256 id, ProjectStatus status);


struct Project {
    address token;
    uint256 initialTokenAmount;
    uint256 raised; // in ETH
    uint256 startTime;
    uint256 endTime;
    address creator;
    address[] contributors;
    ProjectStatus status;  // gets changed when endPresale is called
    PoolType poolType;
    address pool;
    uint256 priceAfterFailure;
    bool creatorClaimedLockedTokens;
}

contract BondingCurvePresaleUtils is Presale {
    uint256 constant internal PRICE_CHANGE_SLOPE = 0.01e18;  // slope
    uint256 constant internal BASE_PRICE = 0.01e18;  // base price
    uint256 constant internal LOCK_PERIOD = 6 * 30 * 24 * 60 * 60; // 6 months
    uint256 constant internal LOCK_PERCENTAGE = 10e16; // 10%
    mapping (uint256 id => Project project) internal s_projectFromId;

    constructor(address _feeCollector, address _weth, uint256 _successfulEndFee) 
        Presale(_feeCollector, _weth, _successfulEndFee) 
    {}

    modifier validId(uint256 _id) {
        Check.validId(_id, s_lastProjectId);
        _;
    }

    function createPresaleChecks(uint256 _startTime, uint256 _endTime, uint256 _initialTokenAmount) internal {
        Check.startTimeIsInTheFuture(_startTime);
        Check.endTimeIsAfterStartTime(_startTime, _endTime);
        Check.initialTokenAmountIsEven(_initialTokenAmount);
    }

    function joinProjectPresaleChecks(uint256 _id) internal {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasStarted(s_projectFromId[_id].startTime, _id);
        Check.projectHasNotEnded(projectHasEnded(_id), _id);
        Check.thereAreRemainingTokens(getRemainingTokens(_id), _id);
        Check.msgValueIsGreaterThanZero();
    }

    function leaveOngoingProjectPresaleChecks(uint256 _id, uint256 _tokenAmount) internal {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasStarted(s_projectFromId[_id].startTime, _id);
        Check.projectHasNotEnded(projectHasEnded(_id), _id);
        Check.tokenAmountIsGreaterThanZero(_tokenAmount);
        Check.userHasTokenBalance(IERC20(s_projectFromId[_id].token).balanceOf(msg.sender), _tokenAmount, _id);
    }

    function leaveUnsuccessfulProjectPresaleChecks(uint256 _id) internal returns(uint256) {
        Check.projectHasFailed(s_projectFromId[_id].status != ProjectStatus.Failed, _id);
        Check.userHasContributed(contributorExists(_id, msg.sender), _id, msg.sender);
        uint256 userTokenBalance = IERC20(s_projectFromId[_id].token).balanceOf(msg.sender); 
        Check.userHasTokenBalance(IERC20(s_projectFromId[_id].token).balanceOf(msg.sender), userTokenBalance, _id);
        return userTokenBalance;
    }

    function endPresaleChecks(uint256 _id) internal {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasEnded(projectHasEnded(_id), _id);
    }

    function claimLockedTokensChecks(uint256 _id) internal {
        Check.msgSenderIsProjectCreator(s_projectFromId[_id].creator == msg.sender);
        Check.projectIsSuccessful(s_projectFromId[_id].status == ProjectStatus.Success, _id);
        Check.lockPeriodIsOver(s_projectFromId[_id].startTime + LOCK_PERIOD, _id);
        Check.creatorHasNotClaimedLockedTokens(s_projectFromId[_id].creatorClaimedLockedTokens, _id);
    }

    // Get Bonding Curve Presale Project
    function getBCPProject(uint256 _id) external view returns (Project memory) {
        return s_projectFromId[_id];
    }

    /// Public ///

    function getSoftCap(uint256 _id) public view returns (uint256) {
        return getMaxPresaleTokenAmount(_id) * SOFTCAP_PERCENTAGE / DECIMALS;
    }

    function getTotalTokensOwed(uint256 _id) public view returns (uint256) {
        return s_projectFromId[_id].initialTokenAmount - IERC20(s_projectFromId[_id].token).balanceOf(address(this));
    }

    function getRemainingTokens(uint256 _id) public view returns (uint256) {
        // max tokens that can be presold
        uint256 maxTokensToBeDistributed = getMaxPresaleTokenAmount(_id);
        // tokens that can be presold
        uint256 remainingTokens = maxTokensToBeDistributed - getTotalTokensOwed(_id);
        return remainingTokens;
    }

    function calculateBuyAmount(uint256 ethAmount, uint256 supply) public pure returns (uint256) {
        uint256 price = calculatePrice(supply);
        return ethAmount * DECIMALS / price;
    }

    function calculateSellAmount(uint256 tokenAmount, uint256 supply) public pure returns (uint256) {
        uint256 price = calculatePrice(supply - tokenAmount);
        return tokenAmount * price / DECIMALS;
    }

    function calculatePrice(uint256 supply) public pure returns (uint256) {
        return PRICE_CHANGE_SLOPE * supply / DECIMALS + BASE_PRICE;
    }

    /// Internal ///

    function _updateProjectStatus(uint256 _id) internal {
        if (projectSuccessful(_id)) {
            s_projectFromId[_id].status = ProjectStatus.Success;
        } else {
            s_projectFromId[_id].status = ProjectStatus.Failed;
        }
        emit ProjectStatusUpdated(_id, s_projectFromId[_id].status);
    }

    function getMaxPresaleTokenAmount(uint256 _id) internal view returns (uint256) {
        return s_projectFromId[_id].initialTokenAmount / 2;
    }

    function projectHasEnded(uint256 _id) internal view returns (bool) {
        return s_projectFromId[_id].endTime < block.timestamp || getRemainingTokens(_id) == 0;
    }

    function projectSuccessful(uint256 _id) internal view returns (bool) {
        return getTotalTokensOwed(_id) >= getSoftCap(_id);
    }

    function contributorExists(uint256 _id, address _contributor) internal view returns(bool) {
        uint256 amount = IERC20(s_projectFromId[_id].token).balanceOf(_contributor);
        if (amount > 0) {
            return true;
        }
        return false;
    }
}