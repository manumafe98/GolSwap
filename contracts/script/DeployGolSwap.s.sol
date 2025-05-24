// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {GolSwap} from "../src/GolSwap.sol";
import {Gol} from "../src/Gol.sol";

contract DeployGolSwap is Script {
    string private constant NAME = "GOL";
    string private constant SYMBOL = "GOL";

    function run() public returns (GolSwap, Gol) {
        vm.startBroadcast(msg.sender);

        Gol gol = new Gol(NAME, SYMBOL);
        GolSwap golSwap = new GolSwap(address(gol));

        vm.stopBroadcast();
        return (golSwap, gol);
    }
}
