// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "./Uniswap/IWETH9.sol";
import {ERC20Ownable} from "./ERC20Ownable.sol";
import {PoolDeployer} from "./utils/PoolDeployer.sol";
import {Presale, ProjectStatus} from "./utils/Presale.sol";
import {Check} from "./lib/Check.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BondingCurvePresale is PoolDeployer, Presale {
    using Math for uint256;

    struct Project {
        address token;
        uint256 raised; // in ETH
        uint256 startTime;
        uint256 endTime;
        address creator;
        address[] contributors;
        ProjectStatus status;  // gets changed when endPresale is called
        address pool;
        uint256 priceAfterFailure;
        bool hasBeenInitialized;
    }

    mapping (uint256 id => Project project) private s_projectFromId;
    uint256 private immutable i_a; // slope of the bonding curve
    uint256 private immutable i_minInitialEthAmount;
    uint256 private s_swapFee;
    uint256 private s_maxSupply;

    event ProjectCreated(uint256 id, address token, uint256 totalSupply, uint256 startTime, uint256 endTime);
    event UserBoughtTokens(uint256 id, address contributor, uint256 tokenAmount, uint256 ethPaid);
    event UserSoldTokens(uint256 id, address contributor, uint256 tokenAmount, uint256 ethReceived);
    event UserLeftUnsuccessfulProject(uint256 id, address contributor, uint256 etherToGiveBack);
    event ProjectStatusUpdated(uint256 id, ProjectStatus status);
    
    constructor(
        uint256 successfulEndFee,
        address feeCollector,
        uint256 a,
        uint256 minInitialEthAmount,
        uint256 swapFee,
        uint256 maxSupply,
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
        i_a = a;
        i_minInitialEthAmount = minInitialEthAmount;
        s_swapFee = swapFee;
        s_maxSupply = maxSupply;
    }

    modifier validId(uint256 id) {
        Check.validId(id, s_lastProjectId);
        _;
    }

    function createPresale(
        uint256 startTime,
        uint256 endTime,
        string memory name,
		string memory symbol
    ) external payable {
        Check.startTimeIsInTheFuture(startTime);
        Check.endTimeIsAfterStartTime(startTime, endTime);
        // max supply must be an even number so that half goes to presale and half to pool
        Check.maxSupplyIsEvenNumber(s_maxSupply);
        Check.msgValueIsGreaterThanZero();
        Check.MinimumInitialEthAmountPaid(msg.value, i_minInitialEthAmount);

        // Create token supply
        ERC20Ownable token = new ERC20Ownable(name, symbol);
        token.mint(address(this), s_maxSupply);
        // Create project
        s_lastProjectId += 1;
        address[] memory contributors;
        s_projectFromId[s_lastProjectId] = Project({
            token: address(token),
            raised: 0,
            startTime: startTime,
            endTime: endTime,
            creator: msg.sender,
            contributors: contributors,
            status: ProjectStatus.Pending,
            pool: address(0),
            priceAfterFailure: 0,
            hasBeenInitialized: false
        });
        emit ProjectCreated(s_lastProjectId, address(token), s_maxSupply, startTime, endTime);

        // Maybe leakage of ether ?
        uint256 tokensToBuy = estimateTokensFromInitialPrice(msg.value * (1e18 - s_swapFee) / DECIMALS);
        buyTokens(s_lastProjectId, tokensToBuy, 0);
    }
    
    function buyTokens(uint256 id, uint256 tokenAmountToBuy, uint256 expectedEthAmount) public payable nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        if (s_projectFromId[id].hasBeenInitialized == false) {
            s_projectFromId[id].hasBeenInitialized = true;
        } else {
            Check.projectHasStarted(s_projectFromId[id].startTime, id);
        }
        Check.projectHasNotEnded(projectHasEnded(id), id);
        Check.thereAreRemainingTokens(getRemainingTokens(id), id);
        Check.msgValueIsGreaterThanZero();

        // Check if contributions surpass max presale token amount, then give only what is left
        uint256 tokenAmount = tokenAmountToBuy;
        if (getRemainingTokens(id) < tokenAmountToBuy) {
            tokenAmount = getRemainingTokens(id);
        }

        uint256 oldSupply = getSupply(id);
        uint256 ethAmount = priceToChangeTokenSupply(oldSupply, oldSupply + tokenAmount);
        uint256 requiredEthAmount = ethAmount * (1e18 + s_swapFee) / DECIMALS;
        sendEther(payable(s_feeCollector), ethAmount * s_swapFee / DECIMALS);

        Check.enoughEthSent(msg.value, requiredEthAmount);
        if (expectedEthAmount != 0)
            Check.ethAmountIsNotMoreThanExpected(requiredEthAmount, expectedEthAmount);
        
        // Add contributor to project
        if (!contributorExists(id, msg.sender)) {
            s_projectFromId[id].contributors.push(msg.sender);
        }
        uint256 ethNotUsed = msg.value > requiredEthAmount ? msg.value - requiredEthAmount : 0;
        s_projectFromId[id].raised += (msg.value - ethNotUsed);
        sendEther(payable(msg.sender), ethNotUsed);
        IERC20(s_projectFromId[id].token).transfer(msg.sender, tokenAmount);
        emit UserBoughtTokens(id, msg.sender, tokenAmount, msg.value);
    }

    // Needs user approval
    function sellTokens(uint256 id, uint256 tokenAmountToSell, uint256 expectedEthAmount) external nonReentrant validId(id) {
        Check.projectIsPending(s_projectFromId[id].status == ProjectStatus.Pending, id);
        Check.projectHasStarted(s_projectFromId[id].startTime, id);
        Check.projectHasNotEnded(projectHasEnded(id), id);
        Check.tokenAmountIsGreaterThanZero(tokenAmountToSell);
        Check.userHasEnoughTokenBalance(IERC20(s_projectFromId[id].token).balanceOf(msg.sender), tokenAmountToSell, id);

        uint256 oldSupply = getSupply(id);
        uint256 ethAmount = priceToChangeTokenSupply(oldSupply, oldSupply - tokenAmountToSell);
        sendEther(payable(s_feeCollector), ethAmount * s_swapFee / DECIMALS);
        uint256 ethAmountAfterFee = ethAmount * (1e18 - s_swapFee) / DECIMALS;

        if (expectedEthAmount != 0)
            Check.ethAmountIsNotLessThanExpected(ethAmountAfterFee, expectedEthAmount);

        s_projectFromId[id].raised -= ethAmount;
        IERC20(s_projectFromId[id].token).transferFrom(msg.sender, address(this), tokenAmountToSell);
        sendEther(payable(msg.sender), ethAmountAfterFee);
        emit UserSoldTokens(id, msg.sender, tokenAmountToSell, ethAmount);
    }

    function leaveUnsuccessfulProjectPresale(uint256 id) external nonReentrant validId(id) {
        Check.projectHasFailed(s_projectFromId[id].status != ProjectStatus.Failed, id);
        Check.userHasContributed(contributorExists(id, msg.sender), id, msg.sender);
        uint256 userTokenBalance = IERC20(s_projectFromId[id].token).balanceOf(msg.sender); 
        Check.userHasEnoughTokenBalance(IERC20(s_projectFromId[id].token).balanceOf(msg.sender), userTokenBalance, id);

        // Calculate ether to give back
        uint256 etherToGiveBack = userTokenBalance * s_projectFromId[id].priceAfterFailure / DECIMALS;
        // Burn user tokens
        ERC20Ownable(s_projectFromId[id].token).burn(msg.sender, userTokenBalance);
        // give back ether
        sendEther(payable(msg.sender), etherToGiveBack);
        emit UserLeftUnsuccessfulProject(id, msg.sender, etherToGiveBack);
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
                _sortTokens(i_weth, s_projectFromId[id].token, amountRaisedAfterFees, getSupply(id));
            // Deploy the pool
            s_projectFromId[id].pool = _deployPool(token0, token1, amount0, amount1);
        } else {
            // Calculate price after failure
            s_projectFromId[id].priceAfterFailure = s_projectFromId[id].raised * DECIMALS / getSupply(id);
        }
        // Burn remaining tokens
        uint256 remainingTokens = IERC20(s_projectFromId[id].token).balanceOf(address(this));
        ERC20Ownable(s_projectFromId[id].token).burn(address(this), remainingTokens);
    }

    function setSwapFee(uint256 swapFee) external onlyOwner {
        s_swapFee = swapFee;
    }

    function setTotalSupply(uint256 totalSupply) external onlyOwner {
        s_maxSupply = totalSupply;
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    // Get Bonding Curve Presale Project
    function getBCPProject(uint256 id) external view returns (Project memory) {
        return s_projectFromId[id];
    }

    function getLinearCurveSlope() external view returns (uint256) {
        return i_a;
    }

    function getMinInitialEthAmount() external view returns (uint256) {
        return i_minInitialEthAmount;
    }

    function getSwapFee() external view returns (uint256) {
        return s_swapFee;
    }

    function getTotalSupply() external view returns (uint256) {
        return s_maxSupply;
    }

    function getMaxPresaleAmountThatCanBeRaised() external view returns (uint256) {
        return priceToChangeTokenSupply(0, getMaxPresaleTokenAmount());
    }

    /// Public ///

    function getSoftCap() public view returns (uint256) {
        return getMaxPresaleTokenAmount() * s_softcapPercentage / DECIMALS;
    }

    function getRemainingTokens(uint256 id) public view returns (uint256) {
        // max tokens that can be presold
        uint256 maxTokensToBeDistributed = getMaxPresaleTokenAmount();
        // tokens that can be presold
        uint256 remainingTokens = maxTokensToBeDistributed - getSupply(id);
        return remainingTokens;
    }

    function getMaxPresaleTokenAmount() public view returns (uint256) {
        return s_maxSupply / 2;
    }

    function projectHasEnded(uint256 id) public view returns (bool) {
        return s_projectFromId[id].endTime < block.timestamp || getRemainingTokens(id) == 0;
    }

    function projectSuccessful(uint256 id) public view returns (bool) {
        return getSupply(id) >= getSoftCap();
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

    /**
     * This function returns the price that someone has to pay or be paid in order to change
     * the token supply from supplyBefore to supplyAfter.
     * @dev The price is calculated based on the integral below a linear curve
     * from supplyBefore to supplyAfter or from supplyAfter to supplyBefore.
     * @param supplyBefore Token supply before the supply change
     * @param supplyAfter Token supply after the supply change
     */
    function priceToChangeTokenSupply(uint256 supplyBefore, uint256 supplyAfter) public view returns (uint256) {
        bool buyingTokens = supplyBefore < supplyAfter ? true : false;
        uint256 supplyChange = buyingTokens ? supplyAfter - supplyBefore : supplyBefore - supplyAfter;
        return (i_a * (supplyBefore + supplyAfter) * supplyChange / 2) / (DECIMALS * DECIMALS);
    }

    function estimateTokensFromInitialPrice(uint256 price) public view returns (uint256) {
        return (2 * price * DECIMALS * DECIMALS / i_a).sqrt();
    }

    function getSupply(uint256 id) public view returns (uint256) {
        return s_maxSupply - IERC20(s_projectFromId[id].token).balanceOf(address(this));
    }

    // The cost to buy one token times tokens bought
    function marketCap(uint256 id) public view returns (uint256) {
        return priceToChangeTokenSupply(getSupply(id), getSupply(id) + 1e18) * getSupply(id) / DECIMALS;
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