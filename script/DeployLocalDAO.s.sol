// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {LocalDAO} from "../src/LocalDAO.sol";
import {LocalDAOFactory} from "../src/LocalDAOFactory.sol";

contract DeployLocalDAO is Script {
    // TODO: replace with real stablecoin on Fuji or a mock you deploy first
    address constant STABLE_TOKEN = 0x5425890298aed601595a70AB815c96711a31Bc65;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 1) Deploy implementation
        LocalDAO implementation = new LocalDAO();

        // 2) Deploy factory pointing to implementation
        LocalDAOFactory factory = new LocalDAOFactory(deployer, address(implementation));

        // 3) Create one DAO instance to test
        address daoAddress = factory.createDAO(
            "Essien Town Local DAO",
            "Empowering Essien Town through community investment",
            "Essien Town, Cross River, Nigeria",
            "4.9757,8.3417",
            "540001",
            100,
            STABLE_TOKEN
        );

        vm.stopBroadcast();

        console2.log("Implementation:", address(implementation));
        console2.log("Factory:", address(factory));
        console2.log("First DAO:", daoAddress);
    }
}