// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title InvestmentManager
 * @notice Library for investment lifecycle management
 */
library InvestmentManager {
    // Import Status and Grade enums from LocalDAO
    enum Status { PENDING, ACTIVE, ENDED, INCOMPLETE }
    enum Grade { A, B, C, D }

    /**
     * @notice Check if investment can be activated
     * @param upvotes Current upvoted USDC
     * @param fundNeeded Required funding
     * @param deadline Voting deadline
     * @param currentTime Current block timestamp
     * @return canActivate True if can activate
     */
    function canActivate(
        uint256 upvotes,
        uint256 fundNeeded,
        uint256 deadline,
        uint256 currentTime
    ) internal pure returns (bool) {
        return upvotes >= fundNeeded && currentTime <= deadline;
    }

    /**
     * @notice Check if investment should be marked incomplete
     * @param upvotes Current upvoted USDC
     * @param fundNeeded Required funding
     * @param deadline Voting deadline
     * @param currentTime Current block timestamp
     * @return isIncomplete True if should mark incomplete
     */
    function shouldMarkIncomplete(
        uint256 upvotes,
        uint256 fundNeeded,
        uint256 deadline,
        uint256 currentTime
    ) internal pure returns (bool isIncomplete) {
        return upvotes < fundNeeded && currentTime > deadline;
    }

    /**
     * @notice Check if deadline can be extended
     * @param grade Investment grade
     * @param extensionCount Number of previous extensions
     * @param maxExtensions Maximum allowed extensions
     * @return canExtend True if can extend
     */
    function canExtendDeadline(
        Grade grade,
        uint256 extensionCount,
        uint256 maxExtensions
    ) internal pure returns (bool canExtend) {
        // Only Grade A and B can extend
        if (uint8(grade) > 1) return false; // C or D
        
        // Check extension limit
        return extensionCount < maxExtensions;
    }

    /**
     * @notice Calculate new deadline after extension
     * @param currentDeadline Current deadline timestamp
     * @param additionalDays Days to add
     * @return newDeadline New deadline timestamp
     */
    function calculateNewDeadline(
        uint256 currentDeadline,
        uint256 additionalDays
    ) internal pure returns (uint256 newDeadline) {
        require(additionalDays > 0 && additionalDays <= 90, "Invalid extension");
        newDeadline = currentDeadline + (additionalDays * 1 days);
        return newDeadline;
    }

    /**
     * @notice Check if investment is eligible for yield deposit
     * @param status Current investment status
     * @return isEligible True if can deposit yield
     */
    function canDepositYield(Status status) 
        internal 
        pure 
        returns (bool isEligible) 
    {
        return status == Status.ACTIVE;
    }

    /**
     * @notice Check if investment can be closed
     * @param status Current status
     * @param totalYield Total yield generated
     * @param distributedYield Total yield distributed
     * @return canClose True if can close
     */
    function canCloseInvestment(
        Status status,
        uint256 totalYield,
        uint256 distributedYield
    ) internal pure returns (bool canClose) {
        // Can close if ACTIVE and all yield distributed
        if (status != Status.ACTIVE) return false;
        return totalYield == distributedYield;
    }

    /**
     * @notice Validate investment parameters
     * @param fundNeeded Required funding
     * @param expectedYield Expected yield percentage
     * @param deadline Deadline in days
     * @return isValid True if parameters valid
     */
    function validateInvestmentParams(
        uint256 fundNeeded,
        uint256 expectedYield,
        uint256 deadline
    ) internal pure returns (bool isValid) {
        if (fundNeeded == 0) return false;
        if (expectedYield > 100) return false; // Max 100% yield
        if (deadline == 0 || deadline > 365) return false; // Max 1 year
        return true;
    }
}

