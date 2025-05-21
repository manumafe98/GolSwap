// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Gol} from "../src/Gol.sol";
import {DeployGol} from "../script/DeployGol.s.sol";

contract GolTest is Test {
    Gol public gol;

    function setUp() external {
        DeployGol deployer = new DeployGol();
        gol = deployer.run();
    }

    function testNameAndSymbol() public view {
        assertEq(keccak256(bytes(gol.name())), keccak256(bytes("GOL")));
        assertEq(keccak256(bytes(gol.symbol())), keccak256(bytes("GOL")));
    }

    function testTotalSupply() public view {
        assertEq(gol.totalSupply(), 100 ether);
    }

    function testDecimals() public view {
        assertEq(gol.decimals(), 18);
    }
}
