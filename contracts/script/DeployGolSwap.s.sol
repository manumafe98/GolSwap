// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {GolSwap} from "../src/GolSwap.sol";
import {Gol} from "../src/Gol.sol";
import {DeployGol} from "../script/DeployGol.s.sol";

contract DeployGolSwap is Script {
    DeployGol golDeployer;

    function run() public returns(GolSwap, Gol) {
        golDeployer = new DeployGol();
        Gol golToken = golDeployer.run();

        vm.startBroadcast();

        GolSwap golSwap = new GolSwap(address(golToken));

        vm.stopBroadcast();
        return (golSwap, golToken);
    }
}
