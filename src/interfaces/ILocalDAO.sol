// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILocalDAO
 * @notice Interface for LocalDAO contract
 * @dev Used by Factory for standardized DAO interactions
 * @dev Enums are defined in LocalDAO contract to avoid duplication
 */
interface ILocalDAO {
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

