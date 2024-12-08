// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {ERC20Ownable} from "./ERC20Ownable.sol";
import {PoolDeployer, PoolType} from "./utils/PoolDeployer.sol";
import {Presale, ProjectStatus} from "./utils/Presale.sol";
import {Check} from "./lib/Check.sol";


contract BondingCurvePresale is PoolDeployer, Presale {
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

    uint256 private constant PRICE_CHANGE_SLOPE = 0.01e18;  // slope
    uint256 private constant BASE_PRICE = 0.01e18;  // base price
    uint256 private constant LOCK_PERIOD = 6 * 30 * 24 * 60 * 60; // 6 months
    uint256 private constant LOCK_PERCENTAGE = 10e16; // 10%
    mapping (uint256 id => Project project) private s_projectFromId;

    event ProjectCreated(uint256 id, address token, uint256 initialTokenAmount, uint256 startTime, uint256 endTime);
    event UserJoinedProject(uint256 id, address contributor, uint256 tokenAmount, uint256 tokenPrice);
    event UserLeftProject(uint256 id, address contributor, uint256 etherToGiveBack);
    event UserLeftPendingProject(uint256 id, address contributor, uint256 tokenAmount, uint256 priceAfterFailure);
    event LockedTokensClaimed(uint256 id, address contributor);
    event ProjectStatusUpdated(uint256 id, ProjectStatus status);
    
    constructor(
        uint256 successfulEndFee,
        address feeCollector,
        address uniFactory,
        address nonfungiblePositionManager,
        address weth,
        address balancerVault,
        address balancerRouter,
        address CPFactory,
        address balancerPermit2
    ) 
        Presale(feeCollector, weth, successfulEndFee) 
        PoolDeployer(
            uniFactory,
            nonfungiblePositionManager,
            balancerVault,
            balancerRouter,
            CPFactory,
            balancerPermit2
        )
    {}

    modifier validId(uint256 id) {
        Check.validId(id, s_lastProjectId);
        _;
    }

    function createPresale(
        uint256 initialTokenAmount, // must be even number so that half goes to presale and half to pool
        uint256 startTime,
        uint256 endTime,
        PoolType poolType,
        string memory name,
		string memory symbol
    ) external nonReentrant {  // probably does not need nonReentrant but just in case
        Check.startTimeIsInTheFuture(startTime);
        Check.endTimeIsAfterStartTime(startTime, endTime);
        Check.initialTokenAmountIsEven(initialTokenAmount);

        // Create token supply
        ERC20Ownable token = new ERC20Ownable(name, symbol);
        token.mint(address(this), initialTokenAmount);
        // Create project
        s_lastProjectId += 1;
        address[] memory contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: address(token),
            initialTokenAmount: initialTokenAmount,
            raised: 0,
            startTime: startTime,
            endTime: endTime,
            creator: msg.sender,
            contributors: contributors,
            status: ProjectStatus.Pending,
            poolType: poolType,
            pool: address(0),
            priceAfterFailure: 0,
            creatorClaimedLockedTokens: false
        });
        emit ProjectCreated(s_lastProjectId, address(token), initialTokenAmount, startTime, endTime);
    }
    
    function joinProjectPresale(uint256 id, uint256 expectedTokenAmount) external payable nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        Check.projectHasStarted(s_projectFromId[id].startTime, id);
        Check.projectHasNotEnded(projectHasEnded(id), id);
        Check.thereAreRemainingTokens(getRemainingTokens(id), id);
        Check.msgValueIsGreaterThanZero();

        uint256 oldSupply = s_projectFromId[id].initialTokenAmount - IERC20(s_projectFromId[id].token).balanceOf(address(this));
        uint256 tokenAmount = calculateBuyAmount(msg.value, oldSupply);
        
        // Check if contributions surpass max presale token amount, then give only what is left
        if (getRemainingTokens(id) < tokenAmount) {
            tokenAmount = getRemainingTokens(id);
        }
        
        Check.tokenAmountIsNotLessThanExpected(tokenAmount, expectedTokenAmount);

        // Add contributor to project
        if (!contributorExists(id, msg.sender)) {
            s_projectFromId[id].contributors.push(msg.sender);
        }
        s_tokensOwedToContributor[id][msg.sender] += tokenAmount;
        s_projectFromId[id].raised += msg.value;
        IERC20(s_projectFromId[id].token).transfer(msg.sender, tokenAmount);
        emit UserJoinedProject(id, msg.sender, tokenAmount, calculatePrice(oldSupply));
    }

    // Sell back all the tokens that the user has
    function leaveOngoingProjectPresale(uint256 id, uint256 expectedEthAmount) external nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        Check.projectHasStarted(s_projectFromId[id].startTime, id);
        Check.projectHasNotEnded(projectHasEnded(id), id);
        uint256 tokenAmount = s_tokensOwedToContributor[id][msg.sender];
        Check.tokenAmountIsGreaterThanZero(tokenAmount);
        Check.userHasTokenBalance(IERC20(s_projectFromId[id].token).balanceOf(msg.sender), tokenAmount, id);

        uint256 oldSupply = s_projectFromId[id].initialTokenAmount - IERC20(s_projectFromId[id].token).balanceOf(address(this));
        uint256 ethAmount = calculateSellAmount(tokenAmount, oldSupply);
        Check.ethAmountIsNotLessThanExpected(ethAmount, expectedEthAmount);

        s_projectFromId[id].raised -= ethAmount;
        s_tokensOwedToContributor[id][msg.sender] = 0;
        IERC20(s_projectFromId[id].token).transferFrom(msg.sender, address(this), tokenAmount);
        sendEther(payable(msg.sender), ethAmount);
        emit UserLeftPendingProject(id, msg.sender, tokenAmount, calculatePrice(oldSupply));
    }

    function leaveUnsuccessfulProjectPresale(uint256 id) external nonReentrant validId(id) {
        Check.projectHasFailed(s_projectFromId[id].status != ProjectStatus.Failed, id);
        Check.userHasContributed(contributorExists(id, msg.sender), id, msg.sender);
        uint256 userTokenBalance = IERC20(s_projectFromId[id].token).balanceOf(msg.sender); 
        Check.userHasTokenBalance(IERC20(s_projectFromId[id].token).balanceOf(msg.sender), userTokenBalance, id);

        // Calculate ether to give back
        uint256 etherToGiveBack = userTokenBalance * s_projectFromId[id].priceAfterFailure / DECIMALS;
        // Burn user tokens
        ERC20Ownable(s_projectFromId[id].token).burn(msg.sender, userTokenBalance);
        // give back ether
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
            // Calculate successful-end fee (in ether)
            uint256 successfulEndFeeAmount = s_projectFromId[id].raised * i_successfulEndFee / DECIMALS;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[id].creator), successfulEndFeeAmount);
            // Reduce amount raised by project creator fee and fee collector fee
            uint256 amountRaisedAfterFees = s_projectFromId[id].raised - (2 * successfulEndFeeAmount);
            // Wrap ETH into WETH
            IWETH9(i_weth).deposit{value: amountRaisedAfterFees}();
            // Sort the tokens
            (address token0, address token1, uint256 amount0, uint256 amount1) = 
                _sortTokens(i_weth, s_projectFromId[id].token, amountRaisedAfterFees, getTotalTokensOwed(id));
            // Deploy the pool
            s_projectFromId[id].pool = _deployPool(s_projectFromId[id].poolType, token0, token1, amount0, amount1);
        } else {
            // Calculate price after failure
            s_projectFromId[id].priceAfterFailure = s_projectFromId[id].raised * DECIMALS / getTotalTokensOwed(id);
        }
        // Burn remaining tokens
        uint256 remainingTokens = IERC20(s_projectFromId[id].token).balanceOf(address(this));
        ERC20Ownable(s_projectFromId[id].token).burn(address(this), remainingTokens);
        // Mint the locked tokens so that the project creator can claim them when lock period is over
        uint256 lockAmount = getTotalTokensOwed(id) * LOCK_PERCENTAGE / DECIMALS;
        ERC20Ownable(s_projectFromId[id].token).mint(address(this), lockAmount);
    }

    function claimLockedTokens(uint256 id) external nonReentrant validId(id) {
        Check.msgSenderIsProjectCreator(s_projectFromId[id].creator == msg.sender);
        Check.projectIsSuccessful(s_projectFromId[id].status == ProjectStatus.Success, id);
        Check.lockPeriodIsOver(s_projectFromId[id].startTime + LOCK_PERIOD, id);
        Check.creatorHasNotClaimedLockedTokens(s_projectFromId[id].creatorClaimedLockedTokens, id);

        s_projectFromId[id].creatorClaimedLockedTokens = true;
        emit LockedTokensClaimed(id, msg.sender);
        uint256 lockedAmount = s_projectFromId[id].raised * LOCK_PERCENTAGE / DECIMALS;
        sendEther(payable(msg.sender), lockedAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /// External ///

    // Get Bonding Curve Presale Project
    function getBCPProject(uint256 id) external view returns (Project memory) {
        return s_projectFromId[id];
    }

    /// Public ///

    function getSoftCap(uint256 id) public view returns (uint256) {
        return getMaxPresaleTokenAmount(id) * SOFTCAP_PERCENTAGE / DECIMALS;
    }

    function getTotalTokensOwed(uint256 id) public view returns (uint256) {
        return s_projectFromId[id].initialTokenAmount - IERC20(s_projectFromId[id].token).balanceOf(address(this));
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

    function contributorExists(uint256 id, address _contributor) public view returns(bool) {
        uint256 amount = IERC20(s_projectFromId[id].token).balanceOf(_contributor);
        if (amount > 0) {
            return true;
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                          PRICE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _updateProjectStatus(uint256 id) private {
        if (projectSuccessful(id)) {
            s_projectFromId[id].status = ProjectStatus.Success;
        } else {
            s_projectFromId[id].status = ProjectStatus.Failed;
        }
        emit ProjectStatusUpdated(id, s_projectFromId[id].status);
    }
}