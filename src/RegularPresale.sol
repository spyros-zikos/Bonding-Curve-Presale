// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PriceConverter} from "./lib/PriceConverter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {BalancerPoolDeployer} from "./Balancer/BalancerPoolDeployer.sol";
import {UniswapPoolDeployer} from "./Uniswap/UniswapPoolDeployer.sol";
import {Check} from "./lib/Check.sol";


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
event UniswapPoolDeployed(address pool);
event BalancerPoolDeployed(address pool);


enum ProjectStatus {
    Pending,
    Success,
    Failed
}


enum PoolType {
    Uniswap,
    Balancer
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
    ProjectStatus status;  // gets changed when endPresale is called
    PoolType poolType;
}


contract RegularPresale is Ownable, ReentrancyGuard, BalancerPoolDeployer, UniswapPoolDeployer {
    uint256 constant DECIMALS = 1e18;
    uint24 constant UNISWAP_SWAP_FEE = 3000;  // 0.3%, don't change this
    uint256 constant BALANCER_SWAP_FEE = 0.3e16;  // 0.3%, don't change this
    uint256 private s_creationFee;
    uint256 private s_successfulEndFee; // percentage, e.g. 10e16 = 10%
    address private s_feeCollector;
    AggregatorV3Interface private s_priceFeed;
    uint256 private s_lastProjectId; // starts from 1
    mapping (uint256 id => Project project) private s_projectFromId;
    mapping (uint256 id => mapping(address contributor => uint256 tokenAmount)) s_tokensOwedToContributor;
    address private s_weth;

    modifier validId(uint256 _id) {
        Check.validId(_id, s_lastProjectId);
        _;
    }

    constructor(
        uint256 _creationFee,
        uint256 _successfulEndFee,
        address _feeCollector,
        address _priceFeed,
        address _uniFactory,
        address _nonfungiblePositionManager,
        address _weth,  // from uniswap
        address _balancerVault,
        address _balancerRouter,
        address _balancerPermit2
    ) 
        Ownable(msg.sender)
        BalancerPoolDeployer(_balancerVault, _balancerRouter, _balancerPermit2, BALANCER_SWAP_FEE)
        UniswapPoolDeployer(_uniFactory, _nonfungiblePositionManager, UNISWAP_SWAP_FEE)
    {
        s_creationFee = _creationFee;
        s_successfulEndFee = _successfulEndFee;
        s_feeCollector = _feeCollector;
        s_priceFeed = AggregatorV3Interface(_priceFeed);
        s_weth = _weth;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function createPresale(
        address _token,
        uint256 _tokenPrice,
        uint256 _initialTokenAmount, // must be even number so that half goes to presale and half to pool
        uint256 _startTime,
        uint256 _endTime,
        PoolType _poolType
    ) external payable nonReentrant {  // probably does not need nonReentrant but just in case
        Check.tokenIsValid(_token);
        Check.tokenPriceIsValid(_tokenPrice);
        Check.startTimeIsInTheFuture(_startTime);
        Check.endTimeIsAfterStartTime(_startTime, _endTime);
        // Calculate fee paid
        uint256 msgValueInUsd = PriceConverter.getConversionRate(msg.value, s_priceFeed);
        Check.correctFeePaid(msgValueInUsd, s_creationFee);
        Check.initialTokenAmountIsEven(_initialTokenAmount);

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
            status: ProjectStatus.Pending,
            poolType: _poolType
        });
        emit ProjectCreated(s_lastProjectId, _token, _tokenPrice, _initialTokenAmount, _startTime, _endTime);
    }

    function joinProjectPresale(uint256 _id) external payable nonReentrant validId(_id) {
        Check.projectIsPending(s_projectFromId[_id].status != ProjectStatus.Pending, _id);
        Check.projectHasStarted(s_projectFromId[_id].startTime, _id);
        Check.projectHasNotEnded(projectHasEnded(_id), _id);
        Check.thereAreRemainingTokens(getRemainingTokens(_id), _id);

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
        Check.projectHasFailed(s_projectFromId[_id].status != ProjectStatus.Failed, _id);
        Check.userHasContributed(contributorExists(_id, msg.sender), _id, msg.sender);

        // Calculate ether to give back
        uint256 etherToGiveBack = s_tokensOwedToContributor[_id][msg.sender] * s_projectFromId[_id].price / DECIMALS;
        // Reset tokens owed to user
        s_tokensOwedToContributor[_id][msg.sender] = 0;
        // give it back
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftProject(_id, msg.sender, etherToGiveBack);
    }

    // Should be called when presale has pendinig status but has either succeded or time ended
    function endPresale(uint256 _id) external nonReentrant validId(_id) {
        Check.projectIsPending(s_projectFromId[_id].status != ProjectStatus.Pending, _id);
        Check.projectHasEnded(projectHasEnded(_id), _id);

        if (projectSuccessful(_id)) {
            s_projectFromId[_id].status = ProjectStatus.Success;
        } else {
            s_projectFromId[_id].status = ProjectStatus.Failed;
        }

        if (projectSuccessful(_id)) {
            // Distribute tokens to contributors
            for (uint256 i = 0; i < s_projectFromId[_id].contributors.length; i++) {
                address contributor = s_projectFromId[_id].contributors[i];
                uint256 tokensToGive = s_tokensOwedToContributor[_id][contributor];
                IERC20(s_projectFromId[_id].token).transfer(contributor, tokensToGive);
                s_tokensOwedToContributor[_id][contributor] = 0; // that's probably not needed
            }
            // Calculate successful-end fee (in ether)
            uint256 successfulEndFeeAmount = s_projectFromId[_id].raised * s_successfulEndFee / 1e18;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[_id].creator), successfulEndFeeAmount);
            // Reduce amount raised by 2*successfulEndFeeAmount
            // so that successfulEndFeeAmount is sent to creator
            // and successfulEndFeeAmount remains in the contract for the fee collector to collct
            uint256 amountRaisedAfterFees = s_projectFromId[_id].raised - (2 * successfulEndFeeAmount);
            // Wrap ETH into WETH
            IWETH9(s_weth).deposit{value: amountRaisedAfterFees}();
            // Sort the tokens
            (address token0, address token1, uint256 amount0, uint256 amount1) = 
                _sortTokens(s_weth, s_projectFromId[_id].token, amountRaisedAfterFees, getMaxPresaleTokenAmount(_id));
            // Deploy the pool
            _deployPool(_id, token0, token1, amount0, amount1);
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
        Check.etherTransferSuccess(sent, _to, _value);
    }

    function projectHasEnded(uint256 _id) public view returns (bool) {
        return s_projectFromId[_id].endTime < block.timestamp || getRemainingTokens(_id) == 0;
    }

    function projectSuccessful(uint256 _id) public view returns (bool) {
        return getTotalTokensOwed(_id) >= getSoftCap(_id);
    }

    ///// Deploy Pool /////

    function _deployPool(uint256 _id, address _token0, address _token1, uint256 _amount0, uint256 _amount1) private {
        address pool;
        if (s_projectFromId[_id].poolType == PoolType.Uniswap) {
            // Deploy uniswap pool and add the tokens
            pool = deployUniswapPool(_token0, _token1, _amount0, _amount1);
            emit UniswapPoolDeployed(pool);
        } else {
            // Deploy balancer pool and add the tokens
            pool = deployConstantProductPool(_token0, _token1, _amount0, _amount1);
            emit BalancerPoolDeployed(pool);
        }
    }

    ///// Helpers /////

    function _sortTokens(address _token0, address _token1, uint256 _tokenAmount0, uint256 _tokenAmount1) 
        private pure returns (address token0, address token1, uint256 tokenAmount0, uint256 tokenAmount1)
    {
        (token0, token1, tokenAmount0, tokenAmount1) = 
            _token0 < _token1
            ? (_token0, _token1, _tokenAmount0, _tokenAmount1)
            : (_token1, _token0, _tokenAmount1, _tokenAmount0);
    }

    // TODO get stats functions

    // Future: check fees in range 0-100, improve for loops gaswise
}