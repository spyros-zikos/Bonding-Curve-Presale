// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {ERC20Ownable} from "./ERC20Ownable.sol";
import {PoolDeployer, PoolType} from "./utils/PoolDeployer.sol";
import {Presale, ProjectStatus} from "./utils/Presale.sol";
import {BondingCurvePresaleUtils, Project} from "./utils/BondingCurvePresaleUtils.sol";


event ProjectCreated(uint256 id, address token, uint256 initialTokenAmount, uint256 startTime, uint256 endTime);
event UserJoinedProject(uint256 id, address contributor, uint256 tokenAmount, uint256 tokenPrice);
event UserLeftProject(uint256 id, address contributor, uint256 etherToGiveBack);
event UserLeftPendingProject(uint256 id, address contributor, uint256 tokenAmount, uint256 priceAfterFailure);
event LockedTokensClaimed(uint256 id, address contributor);


contract BondingCurvePresale is PoolDeployer, BondingCurvePresaleUtils {
    
    
    constructor(
        uint256 _successfulEndFee,
        address _feeCollector,
        address _uniFactory,
        address _nonfungiblePositionManager,
        address _weth,
        address _balancerVault,
        address _balancerRouter,
        address _CPFactory,
        address _balancerPermit2
    ) 
        BondingCurvePresaleUtils(_feeCollector, _weth, _successfulEndFee)
        PoolDeployer(
            _uniFactory,
            _nonfungiblePositionManager,
            _balancerVault,
            _balancerRouter,
            _CPFactory,
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
    ) external nonReentrant {  // probably does not need nonReentrant but just in case
        createPresaleChecks(_startTime, _endTime, _initialTokenAmount);

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
    
    function joinProjectPresale(uint256 _id) external payable nonReentrant validId(_id) {
        joinProjectPresaleChecks(_id);

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
        IERC20(s_projectFromId[_id].token).transfer(msg.sender, tokenAmount);
        emit UserJoinedProject(_id, msg.sender, tokenAmount, calculatePrice(oldSupply));
    }

    function leaveOngoingProjectPresale(uint256 _id, uint256 _tokenAmount) external nonReentrant validId(_id) {
        leaveOngoingProjectPresaleChecks(_id, _tokenAmount);

        uint256 oldSupply = s_projectFromId[_id].initialTokenAmount - IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        uint256 ethAmount = calculateSellAmount(_tokenAmount, oldSupply);
        
        s_projectFromId[_id].raised -= ethAmount;
        IERC20(s_projectFromId[_id].token).transferFrom(msg.sender, address(this), _tokenAmount);
        sendEther(payable(msg.sender), ethAmount);
        emit UserLeftPendingProject(_id, msg.sender, _tokenAmount, calculatePrice(oldSupply));
    }

    function leaveUnsuccessfulProjectPresale(uint256 _id) external nonReentrant validId(_id) {
        uint256 userTokenBalance = leaveUnsuccessfulProjectPresaleChecks(_id);

        // Calculate ether to give back
        uint256 etherToGiveBack = userTokenBalance * s_projectFromId[_id].priceAfterFailure / DECIMALS;
        // Burn user tokens
        ERC20Ownable(s_projectFromId[_id].token).burn(msg.sender, userTokenBalance);
        // give back ether
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftProject(_id, msg.sender, etherToGiveBack);
    }

    // Should be called when presale has pendinig status but has either succeded or time ended
    function endPresale(uint256 _id) external nonReentrant validId(_id) {
        endPresaleChecks(_id);

        // Update project status
        _updateProjectStatus(_id);
        
        if (projectSuccessful(_id)) {
            // Calculate successful-end fee (in ether)
            uint256 successfulEndFeeAmount = s_projectFromId[_id].raised * s_successfulEndFee / DECIMALS;
            // Send ether as fee to project creator
            sendEther(payable(s_projectFromId[_id].creator), successfulEndFeeAmount);
            // Reduce amount raised by project creator fee and fee collector fee
            uint256 amountRaisedAfterFees = s_projectFromId[_id].raised - (2 * successfulEndFeeAmount);
            // Wrap ETH into WETH
            // IWETH9(s_weth).approve()
            IWETH9(s_weth).deposit{value: amountRaisedAfterFees}();
            // Sort the tokens
            (address token0, address token1, uint256 amount0, uint256 amount1) = 
                _sortTokens(s_weth, s_projectFromId[_id].token, amountRaisedAfterFees, getTotalTokensOwed(_id));
            // Deploy the pool
            s_projectFromId[_id].pool = _deployPool(s_projectFromId[_id].poolType, token0, token1, amount0, amount1);
        } else {
            // Calculate price after failure
            s_projectFromId[_id].priceAfterFailure = s_projectFromId[_id].raised * DECIMALS / getTotalTokensOwed(_id);
        }
        // Burn remaining tokens
        uint256 remainingTokens = IERC20(s_projectFromId[_id].token).balanceOf(address(this));
        ERC20Ownable(s_projectFromId[_id].token).burn(address(this), remainingTokens);
        // Mint the locked tokens so that the project creator can claim them when lock period is over
        uint256 lockAmount = getTotalTokensOwed(_id) * LOCK_PERCENTAGE / DECIMALS;
        ERC20Ownable(s_projectFromId[_id].token).mint(address(this), lockAmount);
    }

    function claimLockedTokens(uint256 _id) external nonReentrant validId(_id) {
        claimLockedTokensChecks(_id);

        s_projectFromId[_id].creatorClaimedLockedTokens = true;
        emit LockedTokensClaimed(_id, msg.sender);
        uint256 lockedAmount = s_projectFromId[_id].raised * LOCK_PERCENTAGE / DECIMALS;
        sendEther(payable(msg.sender), lockedAmount);
    }
}