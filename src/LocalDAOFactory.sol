// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LocalDAO} from "./LocalDAO.sol";

/**
 * @title LocalDAOFactory
 * @notice Factory contract for deploying and tracking LocalDAO instances
 */
contract LocalDAOFactory is Ownable {
    // ===== STATE VARIABLES =====
    address[] public allDAOs;
    mapping(address => bool) public isDAO;
    
    struct DAOMetadata {
        string name;
        string location;
        address creator;
        uint256 createdAt;
        bool isActive;
    }
    
    mapping(address => DAOMetadata) public daoInfo;

    // ===== CONSTRUCTOR =====
    constructor(address _owner) Ownable(_owner) {}

    // ===== CORE FUNCTIONS =====
    /**
     * @notice Deploy a new Local DAO
     * @param name DAO name (e.g., "Essien Town Local DAO")
     * @param description DAO mission statement
     * @param location Geographic location
     * @param coordinates GPS coordinates
     * @param postalCode Postal/ZIP code
     * @param maxMembership Maximum members allowed
     * @param usdcAddress USDC token address on this chain
     * @return daoAddress Address of newly deployed DAO
     */
    function createDAO(
        string memory name,
        string memory description,
        string memory location,
        string memory coordinates,
        string memory postalCode,
        uint256 maxMembership,
        address usdcAddress
    ) external returns (address daoAddress) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(location).length > 0, "Location required");
        require(maxMembership > 0, "Invalid max membership");
        require(usdcAddress != address(0), "Invalid USDC address");

        LocalDAO newDAO = new LocalDAO(
            msg.sender,
            name,
            description,
            location,
            coordinates,
            postalCode,
            maxMembership,
            usdcAddress
        );

        daoAddress = address(newDAO);
        
        allDAOs.push(daoAddress);
        isDAO[daoAddress] = true;
        daoInfo[daoAddress] = DAOMetadata({
            name: name,
            location: location,
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true
        });

        emit DAOCreated(daoAddress, name, location, msg.sender, block.timestamp);
        
        return daoAddress;
    }

    /**
     * @notice Get all deployed DAOs
     * @return Array of DAO contract addresses
     */
    function getAllDAOs() external view returns (address[] memory) {
        return allDAOs;
    }

    /**
     * @notice Get active DAOs only
     * @return Array of active DAO addresses
     */
    function getActiveDAOs() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allDAOs.length; i++) {
            if (daoInfo[allDAOs[i]].isActive) {
                activeCount++;
            }
        }

        address[] memory activeDAOs = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allDAOs.length; i++) {
            if (daoInfo[allDAOs[i]].isActive) {
                activeDAOs[index] = allDAOs[i];
                index++;
            }
        }
        return activeDAOs;
    }

    /**
     * @notice Verify if address is a valid DAO
     * @param daoAddress Address to check
     * @return bool True if valid DAO
     */
    function isValidDAO(address daoAddress) external view returns (bool) {
        return isDAO[daoAddress] && daoInfo[daoAddress].isActive;
    }

    /**
     * @notice Get DAO metadata
     * @param daoAddress DAO contract address
     * @return DAOMetadata struct
     */
    function getDAOMetadata(address daoAddress) 
        external 
        view 
        returns (DAOMetadata memory) 
    {
        require(isDAO[daoAddress], "Invalid DAO address");
        return daoInfo[daoAddress];
    }

    /**
     * @notice Emergency function to mark DAO inactive
     * @dev Only factory owner can call
     * @param daoAddress DAO to deactivate
     */
    function deactivateDAO(address daoAddress) external onlyOwner {
        require(isDAO[daoAddress], "Invalid DAO address");
        require(daoInfo[daoAddress].isActive, "DAO already inactive");

        daoInfo[daoAddress].isActive = false;

        emit DAODeactivated(daoAddress, block.timestamp);
    }

    // ===== EVENTS =====
    event DAOCreated(
        address indexed daoAddress,
        string name,
        string location,
        address indexed creator,
        uint256 timestamp
    );

    event DAODeactivated(
        address indexed daoAddress,
        uint256 timestamp
    );
}

