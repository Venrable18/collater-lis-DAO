// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title YieldCalculator
 * @notice Library for yield distribution calculations
 * @dev Uses safe math and proportional distribution
 */
library YieldCalculator {
    /**
     * @notice Calculate user's share of yield
     * @param userStake User's staked USDC amount
     * @param totalStaked Total USDC staked in investment
     * @param totalYield Total yield to distribute
     * @return userYield User's proportional yield amount
     */
    function calculateUserYield(
        uint256 userStake,
        uint256 totalStaked,
        uint256 totalYield
    ) internal pure returns (uint256 userYield) {
        require(totalStaked > 0, "No stakes");
        require(userStake <= totalStaked, "Invalid stake");
        
        // Formula: (userStake / totalStaked) * totalYield
        // Using safe math to prevent overflow
        userYield = (userStake * totalYield) / totalStaked;
        
        return userYield;
    }

    /**
     * @notice Calculate yield percentage
     * @param yieldAmount Yield generated
     * @param principalAmount Original investment
     * @return yieldPercentage Yield as percentage (with 2 decimals)
     */
    function calculateYieldPercentage(
        uint256 yieldAmount,
        uint256 principalAmount
    ) internal pure returns (uint256 yieldPercentage) {
        require(principalAmount > 0, "Invalid principal");
        
        // Returns percentage with 2 decimal places
        // e.g., 525 = 5.25%
        yieldPercentage = (yieldAmount * 10000) / principalAmount;
        
        return yieldPercentage;
    }

    /**
     * @notice Calculate expected yield amount from percentage
     * @param principal Investment amount
     * @param yieldPercentage Expected yield percentage (e.g., 5 = 5%)
     * @return expectedYield Expected yield amount
     */
    function calculateExpectedYield(
        uint256 principal,
        uint256 yieldPercentage
    ) internal pure returns (uint256 expectedYield) {
        expectedYield = (principal * yieldPercentage) / 100;
        return expectedYield;
    }

    /**
     * @notice Validate yield distribution doesn't exceed total
     * @param distributedAmount Already distributed
     * @param newAmount Amount to distribute
     * @param totalAvailable Total available yield
     * @return isValid True if distribution is valid
     */
    function validateDistribution(
        uint256 distributedAmount,
        uint256 newAmount,
        uint256 totalAvailable
    ) internal pure returns (bool isValid) {
        return (distributedAmount + newAmount) <= totalAvailable;
    }
}

