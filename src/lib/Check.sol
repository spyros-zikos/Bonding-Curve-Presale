// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

error InvalidProjectId(uint256 id);

error InvalidTokenAddress(address token);
error InvalidTokenPrice(uint256 tokenPrice);
error StartTimeMustBeInFuture(uint256 startTime, uint256 currentTime);
error EndTimeMustBeAfterStartTime(uint256 startTime, uint256 endTime);
error IncorrectCreationFee(uint256 feePaid, uint256 actualFee);
error InitialTokenAmountMustBeEven(uint256 initialTokenAmount);

error ProjectIsNotPending(uint256 id);
error ProjectHasNotStarted(uint256 id);
error NoMoreTokensToGive(uint256 id);
error ProjectHasEnded(uint256 id);

error ProjectHasNotFailed(uint256 id);
error UserHasNotContributed(uint256 id, address contributor);
error ProjectHasNotEnded(uint256 id);

error EtherTransferFailed(address to, uint256 value);
error MsgValueIsZero();
error UserHasNoTokenBalance(uint256 balance, uint256 tokenAmount, uint256 id);
error tokenAmountIsZero();

library Check {
    function validId(uint256 id, uint256 lastProjectId) internal pure {
        // Check if id is valid
        if (id > lastProjectId || id == 0) {
            revert InvalidProjectId(id);
        }
    }
    function tokenIsValid(address token) internal pure {
        // Check if token address is valid
        if (token == address(0)) {
            revert InvalidTokenAddress(token);
        }
    }
    
    function tokenPriceIsValid(uint256 tokenPrice) internal pure {
        // Check if token price is greater than 0
        if (tokenPrice <= 0) {
            revert InvalidTokenPrice(tokenPrice);
        }
    }
    
    function startTimeIsInTheFuture(uint256 startTime) internal view {
        // Check if startTime is in the future
        if (block.timestamp > startTime) {
            revert StartTimeMustBeInFuture(startTime, block.timestamp);
        }
    }

    function endTimeIsAfterStartTime(uint256 startTime, uint256 endTime) internal pure {
        // Check if endTime is after startTime
        if (endTime <= startTime) {
            revert EndTimeMustBeAfterStartTime(startTime, endTime);
        }
    }

    function correctFeePaid(uint256 feePaid, uint256 actualFee) internal pure {
        // Check if the fee paid is correct
        if (feePaid != actualFee) {
            revert IncorrectCreationFee(feePaid, actualFee);
        }
    }

    function initialTokenAmountIsEven(uint256 initialTokenAmount) internal pure {
        // Check if initial token amount is an even number
        if (initialTokenAmount % 2 != 0) {
            revert InitialTokenAmountMustBeEven(initialTokenAmount);
        }
    }

    function projectIsPending(bool pending, uint256 id) internal pure {
        // Check if project is pending
        if (!pending) {
            revert ProjectIsNotPending(id);
        }
    }

    function projectHasStarted(uint256 startTime, uint256 id) internal view {
        // Check if project has started
        if (startTime > block.timestamp) {
            revert ProjectHasNotStarted(id);
        }
    }

    function thereAreRemainingTokens(uint256 remainingTokens, uint256 _id) internal pure {
        // If no more tokens to give revert
        if (remainingTokens == 0) {
            revert NoMoreTokensToGive(_id);
        }
    }

    function projectHasNotEnded(bool hasEnded, uint256 _id) internal pure {
        // Check if project has not ended
        if (hasEnded) {
            revert ProjectHasEnded(_id);
        }
    }

    function projectHasFailed(bool hasNotFailed, uint256 id) internal pure {
        // Check if project has failed
        if (hasNotFailed) {
            revert ProjectHasNotFailed(id);
        }
    }

    function projectHasEnded(bool hasEnded, uint256 id) internal pure {
        // Check if project has ended
        if (!hasEnded) {
            revert ProjectHasNotEnded(id);
        }
    }

    function userHasContributed(bool hasContributed, uint256 id, address contributor) internal pure {
        // Check if user has contributed
        if (!hasContributed) {
            revert UserHasNotContributed(id, contributor);
        }
    }

    function etherTransferSuccess(bool sent, address to, uint256 value) internal pure {
        // Check if ether transfer was successful
        if (!sent) {
            revert EtherTransferFailed(to, value);
        }
    }

    function msgValueIsGreaterThanZero() internal view {
        // Check if msg.value is greater than 0
        if (msg.value == 0) {
            revert MsgValueIsZero();
        }
    }

    function userHasTokenBalance(uint256 balance, uint256 tokenAmount, uint256 id) internal pure {
        // Check if user has token balance
        if (balance >= tokenAmount) {
            revert UserHasNoTokenBalance(balance, tokenAmount, id);
        }
    }

    function tokenAmountIsGreaterThanZero(uint256 tokenAmount) internal pure {
        // Check if token amount is greater than 0
        if (tokenAmount == 0) {
            revert tokenAmountIsZero();
        }
    }
}