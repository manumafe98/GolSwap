// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {Gol} from "../src/Gol.sol";

contract DeployGol is Script {
    string private constant NAME = "GOL";
    string private constant SYMBOL = "GOL";

    function run() public returns (Gol) {
        vm.startBroadcast();

        Gol gol = new Gol(NAME, SYMBOL);

        vm.stopBroadcast();
        return gol;
    }
}
