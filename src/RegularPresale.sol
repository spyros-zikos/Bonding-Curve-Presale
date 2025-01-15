// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {Presale, ProjectStatus} from "./utils/Presale.sol";
import {PoolDeployer} from "./utils/PoolDeployer.sol";
import {Check} from "./lib/Check.sol";
import {PriceConverter} from "./lib/PriceConverter.sol";


contract RegularPresale is Presale, PoolDeployer {
    struct Project {
        address token;
        uint256 price; // in USD, 18 decimals
        uint256 initialTokenAmount;
        uint256 raised; // in ETH
        uint256 startTime;
        uint256 endTime;
        address creator;
        address[] contributors;
        ProjectStatus status;  // gets changed when endPresale is called
        address pool;
    }

    uint256 private s_creationFee;
    AggregatorV3Interface private s_priceFeed;
    mapping (uint256 id => Project project) private s_projectFromId;

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
    event ProjectStatusUpdated(uint256 id, ProjectStatus status);

    modifier validId(uint256 id) {
        Check.validId(id, s_lastProjectId);
        _;
    }

    constructor(
        uint256 creationFee,
        uint256 successfulEndFee,
        address feeCollector,
        address priceFeed,
        address uniFactory,
        address nonfungiblePositionManager,
        address weth
    ) 
        Presale(feeCollector, weth, successfulEndFee)
        PoolDeployer(
            uniFactory,
            nonfungiblePositionManager
        )
    {
        s_creationFee = creationFee;
        s_priceFeed = AggregatorV3Interface(priceFeed);
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function createPresale(
        address token,
        uint256 tokenPrice,
        uint256 initialTokenAmount, // must be even number so that half goes to presale and half to pool
        uint256 startTime,
        uint256 endTime
    ) external payable nonReentrant {  // probably does not need nonReentrant but just in case
        Check.tokenIsValid(token);
        Check.tokenPriceIsValid(tokenPrice);
        Check.startTimeIsInTheFuture(startTime);
        Check.endTimeIsAfterStartTime(startTime, endTime);
        Check.msgValueIsGreaterThanZero();
        // Calculate fee paid
        uint256 msgValueInUsd = PriceConverter.getConversionRate(msg.value, s_priceFeed);
        Check.correctFeePaid(msgValueInUsd, s_creationFee);
        Check.initialTokenAmountIsEven(initialTokenAmount);

        // Transfer initial token amount from user to this contract
        IERC20(token).transferFrom(msg.sender, address(this), initialTokenAmount);
        s_lastProjectId += 1;
        address[] memory contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: token,
            price: tokenPrice,
            initialTokenAmount: initialTokenAmount,
            raised: 0,
            startTime: startTime,
            endTime: endTime,
            creator: msg.sender,
            contributors: contributors,
            status: ProjectStatus.Pending,
            pool: address(0)
        });
        emit ProjectCreated(s_lastProjectId, token, tokenPrice, initialTokenAmount, startTime, endTime);
    }

    function joinProjectPresale(uint256 id) external payable nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        Check.projectHasStarted(s_projectFromId[id].startTime, id);
        Check.projectHasNotEnded(projectHasEnded(id), id);
        Check.thereAreRemainingTokens(getRemainingTokens(id), id);
        Check.msgValueIsGreaterThanZero();

        uint256 tokenAmount = msg.value * DECIMALS / s_projectFromId[id].price;
        // Check if contributions surpass max presale token amount, then give only what is left
        if (getRemainingTokens(id) < tokenAmount) {
            tokenAmount = getRemainingTokens(id);
        }
        // Add contributor to project
        if (!contributorExists(id, msg.sender)) {
            s_projectFromId[id].contributors.push(msg.sender);
        }
        s_tokensOwedToContributor[id][msg.sender] += tokenAmount;
        s_projectFromId[id].raised += msg.value;
        emit UserJoinedProject(id, msg.sender, tokenAmount);
    }

    function leaveUnsuccessfulProjectPresale(uint256 id) external nonReentrant validId(id) {
        Check.projectHasFailed(s_projectFromId[id].status != ProjectStatus.Failed, id);
        Check.userHasContributed(contributorExists(id, msg.sender), id, msg.sender);

        // Calculate ether to give back
        uint256 etherToGiveBack = s_tokensOwedToContributor[id][msg.sender] * s_projectFromId[id].price / DECIMALS;
        // Reset tokens owed to user
        s_tokensOwedToContributor[id][msg.sender] = 0;
        // give it back
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftProject(id, msg.sender, etherToGiveBack);
    }

    // Should be called when presale has pendinig status but has either succeded or time ended
    function endPresale(uint256 id) external nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        Check.projectHasEnded(projectHasEnded(id), id);

        // Update project status
        _updateProjectStatus(id);
        
        if (projectSuccessful(id)) {
            // Distribute tokens to contributors
            uint256 contributorsLength = s_projectFromId[id].contributors.length;
            for (uint256 i = 0; i < contributorsLength; i++) {
                address contributor = s_projectFromId[id].contributors[i];
                uint256 tokensToGive = s_tokensOwedToContributor[id][contributor];
                IERC20(s_projectFromId[id].token).transfer(contributor, tokensToGive);
            }
            // Calculate successful-end fee (in ether)
            uint256 successfulEndFeeAmount = s_projectFromId[id].raised * i_successfulEndFee / DECIMALS;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[id].creator), successfulEndFeeAmount);
            // Reduce amount raised by 2*successfulEndFeeAmount
            // so that successfulEndFeeAmount is sent to creator
            // and successfulEndFeeAmount remains in the contract for the fee collector to collct
            uint256 amountRaisedAfterFees = s_projectFromId[id].raised - (2 * successfulEndFeeAmount);
            // Wrap ETH into WETH
            IWETH9(i_weth).deposit{value: amountRaisedAfterFees}();
            // Sort the tokens
            (address token0, address token1, uint256 amount0, uint256 amount1) = 
                _sortTokens(i_weth, s_projectFromId[id].token, amountRaisedAfterFees, getTotalTokensOwed(id));
            // Deploy the pool
            s_projectFromId[id].pool = _deployPool(token0, token1, amount0, amount1);
        }
        // Send remaining/all (depending on project being successful/failed) tokens to project creator
        uint256 remainingTokens = IERC20(s_projectFromId[id].token).balanceOf(address(this));
        if (remainingTokens > 0) {
            IERC20(s_projectFromId[id].token).transfer(s_projectFromId[id].creator, remainingTokens);
        }
    }

    function getRPProject(uint256 id) external view returns (Project memory) {
        return s_projectFromId[id];
    }

    function getTokensOwedToContributor(uint256 id, address contributor) external view returns (uint256) {
        return s_tokensOwedToContributor[id][contributor];
    }

    ////////////////// Public //////////////////////////

    function getSoftCap(uint256 id) public view returns (uint256) {
        return getMaxPresaleTokenAmount(id) * SOFTCAP_PERCENTAGE / DECIMALS;
    }

    function getTotalTokensOwed(uint256 id) public view returns (uint256) {
        uint256 totalTokensOwed = 0;
        uint256 contributorsLength = s_projectFromId[id].contributors.length;
        for (uint256 i = 0; i < contributorsLength; i++) {
            totalTokensOwed += s_tokensOwedToContributor[id][s_projectFromId[id].contributors[i]];
        }
        return totalTokensOwed;
    }

    function getRemainingTokens(uint256 id) public view returns (uint256) {
        // max tokens that can be presold
        uint256 maxTokensToBeDistributed = getMaxPresaleTokenAmount(id);
        // tokens that can be presold
        uint256 remainingTokens = maxTokensToBeDistributed - getTotalTokensOwed(id);
        return remainingTokens;
    }

    function getMaxPresaleTokenAmount(uint256 id) public view returns (uint256) {
        return s_projectFromId[id].initialTokenAmount / 2;
    }

    function projectHasEnded(uint256 id) public view returns (bool) {
        return s_projectFromId[id].endTime < block.timestamp || getRemainingTokens(id) == 0;
    }

    function projectSuccessful(uint256 id) public view returns (bool) {
        return getTotalTokensOwed(id) >= getSoftCap(id);
    }

    function contributorExists(uint256 id, address contributor) public view returns(bool) {
        uint256 amount = s_tokensOwedToContributor[id][contributor];
        if (amount > 0) {
            return true;
        }
        return false;
    }

    function marketCap(uint256 id) public view returns (uint256) {
        return getTotalTokensOwed(id) * s_projectFromId[id].price / DECIMALS;
    }

    ////////////////// Private //////////////////////////

    function _updateProjectStatus(uint256 id) private {
        if (projectSuccessful(id)) {
            s_projectFromId[id].status = ProjectStatus.Success;
        } else {
            s_projectFromId[id].status = ProjectStatus.Failed;
        }
        emit ProjectStatusUpdated(id, s_projectFromId[id].status);
    }
}