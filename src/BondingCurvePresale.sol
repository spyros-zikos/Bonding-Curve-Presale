// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RegularPresale, PoolType, ProjectStatus} from "./RegularPresale.sol";
import {Check} from "./lib/Check.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {ERC20Ownable} from "./ERC20Ownable.sol";


event ProjectCreated(uint256 id, address token, uint256 initialTokenAmount, uint256 startTime, uint256 endTime);
event UserJoinedProject(uint256 id, address contributor, uint256 tokenAmount, uint256 tokenPrice);
event UserLeftProject(uint256 id, address contributor, uint256 etherToGiveBack);
event UserLeftPendingProject(uint256 id, address contributor, uint256 tokenAmount, uint256 priceAfterFailure);
event LockedTokensClaimed(uint256 id, address contributor);

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

contract BondingCurvePresale is RegularPresale{
    uint256 constant PRICE_CHANGE_SLOPE = 0.01e18;  // slope
    uint256 constant BASE_PRICE = 0.01e18;  // base price
    uint256 constant LOCK_PERIOD = 6 * 30 * 24 * 60 * 60; // 6 months
    uint256 constant LOCK_PERCENTAGE = 10e16; // 10%
    mapping (uint256 id => Project project) private s_projectFromId;

    modifier validId(uint256 _id) override {
        Check.validId(_id, s_lastProjectId);
        _;
    }
    
    constructor(
        uint256 _successfulEndFee,
        address _feeCollector,
        address _priceFeed,
        address _uniFactory,
        address _nonfungiblePositionManager,
        address _weth,
        address _balancerVault,
        address _balancerRouter,
        address _balancerPermit2
    ) 
        RegularPresale(
            0,
            _successfulEndFee,
            _feeCollector,
            _priceFeed,
            _uniFactory,
            _nonfungiblePositionManager,
            _weth,
            _balancerVault,
            _balancerRouter,
            _balancerPermit2
        )
    {}

    function createPresale(
        uint256 _initialTokenAmount, // must be even number so that half goes to presale and half to pool
        uint256 _startTime,
        uint256 _endTime,
        PoolType _poolType,
        string memory _name,
		string memory _symbol
    ) external payable nonReentrant {  // probably does not need nonReentrant but just in case
        Check.startTimeIsInTheFuture(_startTime);
        Check.endTimeIsAfterStartTime(_startTime, _endTime);
        Check.initialTokenAmountIsEven(_initialTokenAmount);

        // Create token supply
        ERC20Ownable token = new ERC20Ownable(_name, _symbol);
        token.mint(address(this), _initialTokenAmount);
        // Create project
        s_lastProjectId += 1;
        address[] memory _contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: address(token),
            initialTokenAmount: _initialTokenAmount,
            raised: 0,
            startTime: _startTime,
            endTime: _endTime,
            creator: msg.sender,
            contributors: _contributors,
            status: ProjectStatus.Pending,
            poolType: _poolType,
            pool: address(0),
            priceAfterFailure: 0,
            creatorClaimedLockedTokens: false
        });
        emit ProjectCreated(s_lastProjectId, address(token), _initialTokenAmount, _startTime, _endTime);
    }
    
    function joinProjectPresale(uint256 _id) external payable override nonReentrant validId(_id) {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasStarted(s_projectFromId[_id].startTime, _id);
        Check.projectHasNotEnded(projectHasEnded(_id), _id);
        Check.thereAreRemainingTokens(getRemainingTokens(_id), _id);
        Check.msgValueIsGreaterThanZero();

        uint256 oldSupply = s_projectFromId[_id].initialTokenAmount - IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        uint256 tokenAmount = calculateBuyAmount(msg.value, oldSupply);
        // Check if contributions surpass max presale token amount, then give only what is left
        if (getRemainingTokens(_id) < tokenAmount) {
            tokenAmount = getRemainingTokens(_id);
        }

        // Add contributor to project
        if (!contributorExists(_id, msg.sender)) {
            s_projectFromId[_id].contributors.push(msg.sender);
        }
        s_projectFromId[_id].raised += msg.value;
        IERC20(s_projectFromId[_id].token).transferFrom(address(this), msg.sender, tokenAmount);
        emit UserJoinedProject(_id, msg.sender, tokenAmount, _calculatePrice(oldSupply));
    }

    function leaveOngoingProjectPresale(uint256 _id, uint256 _tokenAmount) external nonReentrant validId(_id) {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasStarted(s_projectFromId[_id].startTime, _id);
        Check.projectHasNotEnded(projectHasEnded(_id), _id);
        Check.tokenAmountIsGreaterThanZero(_tokenAmount);
        Check.userHasTokenBalance(IERC20(s_projectFromId[_id].token).balanceOf(msg.sender), _tokenAmount, _id);

        uint256 oldSupply = s_projectFromId[_id].initialTokenAmount - IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        uint256 ethAmount = calculateSellAmount(_tokenAmount, oldSupply);
        
        s_projectFromId[_id].raised -= ethAmount;
        IERC20(s_projectFromId[_id].token).transferFrom(msg.sender, address(this), _tokenAmount);
        sendEther(payable(msg.sender), ethAmount);
        emit UserLeftPendingProject(_id, msg.sender, _tokenAmount, _calculatePrice(oldSupply));
    }

    function leaveUnsuccessfulProjectPresale(uint256 _id) external override nonReentrant validId(_id) {
        Check.projectHasFailed(s_projectFromId[_id].status != ProjectStatus.Failed, _id);
        Check.userHasContributed(contributorExists(_id, msg.sender), _id, msg.sender);
        uint256 userTokenBalance = IERC20(s_projectFromId[_id].token).balanceOf(msg.sender); 
        Check.userHasTokenBalance(IERC20(s_projectFromId[_id].token).balanceOf(msg.sender), userTokenBalance, _id);

        // Calculate ether to give back
        uint256 etherToGiveBack = userTokenBalance * DECIMALS / s_projectFromId[_id].priceAfterFailure;
        // Get tokens from from user
        IERC20(s_projectFromId[_id].token).transferFrom(msg.sender, address(this), userTokenBalance);
        // give back ether
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftProject(_id, msg.sender, etherToGiveBack);
    }

    // Should be called when presale has pendinig status but has either succeded or time ended
    function endPresale(uint256 _id) external override nonReentrant validId(_id) {
        Check.projectIsPending(s_projectFromId[_id].status == ProjectStatus.Pending, _id);
        Check.projectHasEnded(projectHasEnded(_id), _id);

        // Update project status
        _updateProjectStatus(_id);
        
        if (projectSuccessful(_id)) {
            // Calculate successful-end fee (in ether)
            uint256 successfulEndFeeAmount = s_projectFromId[_id].raised * s_successfulEndFee / DECIMALS;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[_id].creator), successfulEndFeeAmount);
            // Reduce amount raised by 2*successfulEndFeeAmount so that successfulEndFeeAmount is sent 
            // to creator and successfulEndFeeAmount remains in the contract for the fee collector to collector
            uint256 amountRaisedAfterFees = s_projectFromId[_id].raised - (2 * successfulEndFeeAmount);
            // Also subtract the locked tokens
            amountRaisedAfterFees -= s_projectFromId[_id].raised * LOCK_PERCENTAGE / DECIMALS;
            // Wrap ETH into WETH
            IWETH9(s_weth).deposit{value: amountRaisedAfterFees}();
            // Sort the tokens
            (address token0, address token1, uint256 amount0, uint256 amount1) = 
                _sortTokens(s_weth, s_projectFromId[_id].token, amountRaisedAfterFees, getTotalTokensOwed(_id));
            // Deploy the pool
            s_projectFromId[_id].pool = _deployPool(_id, token0, token1, amount0, amount1);
        } else {
            // Calculate price after failure
            s_projectFromId[_id].priceAfterFailure = s_projectFromId[_id].raised * DECIMALS / getTotalTokensOwed(_id);
        }
        // Burn remaining tokens
        uint256 remainingTokens = IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        IERC20(s_projectFromId[_id].token).transfer(address(0), remainingTokens);
    }

    function claimLockedTokens(uint256 _id) external nonReentrant validId(_id) {
        Check.msgSenderIsProjectCreator(s_projectFromId[_id].creator == msg.sender);
        Check.projectIsSuccessful(s_projectFromId[_id].status == ProjectStatus.Success, _id);
        Check.lockPeriodIsOver(s_projectFromId[_id].startTime + LOCK_PERIOD, _id);
        Check.creatorHasNotClaimedLockedTokens(s_projectFromId[_id].creatorClaimedLockedTokens, _id);

        s_projectFromId[_id].creatorClaimedLockedTokens = true;
        emit LockedTokensClaimed(_id, msg.sender);
        uint256 lockedAmount = s_projectFromId[_id].raised * LOCK_PERCENTAGE / DECIMALS;
        sendEther(payable(msg.sender), lockedAmount);
    }

    ////////////////// Public //////////////////////////

    function contributorExists(uint256 _id, address _contributor) public view override returns(bool) {
        uint256 amount = IERC20(s_projectFromId[_id].token).balanceOf(_contributor);
        if (amount > 0) {
            return true;
        }
        return false;
    }

    ////////////////// Private //////////////////////////

    function calculateBuyAmount(uint256 ethAmount, uint256 supply) public pure returns (uint256) {
        uint256 price = _calculatePrice(supply);
        return ethAmount * DECIMALS / price;
    }

    function calculateSellAmount(uint256 tokenAmount, uint256 supply) public pure returns (uint256) {
        uint256 price = _calculatePrice(supply - tokenAmount);
        return tokenAmount * price / DECIMALS;
    }

    function _calculatePrice(uint256 supply) internal pure returns (uint256) {
        return PRICE_CHANGE_SLOPE * supply / DECIMALS + BASE_PRICE;
    }
}