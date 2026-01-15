// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILocalDAO
 * @notice Interface for LocalDAO contract
 * @dev Used by Factory for standardized DAO interactions
 */
interface ILocalDAO {
    // Enums
    enum Status { PENDING, ACTIVE, ENDED, INCOMPLETE }
    enum Category { HEALTH, EDUCATION, ENTERTAINMENT, AGRICULTURE, TECHNOLOGY, RETAIL, OTHER }
    enum Grade { A, B, C, D }

    // View functions
    function name() external view returns (string memory);
    function location() external view returns (string memory);
    function creator() external view returns (address);
    function memberCount() external view returns (uint256);
    function investmentCount() external view returns (uint256);
    function activeInvestmentCount() external view returns (uint256);
    function totalValueLocked() external view returns (uint256);
    
    // State-changing functions
    function pause() external;
    function unpause() external;
}

