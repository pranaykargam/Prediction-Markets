// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarketToken.sol";

contract PredictionMarketTokenTest is Test {
    PredictionMarketToken token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new PredictionMarketToken("YES Token", "YES", address(this));
    }

    function testMinterCanMintAndBurn() public {
        token.mint(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);

        token.burn(alice, 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
    }

    function testOnlyMinterCanMint() public {
        vm.prank(alice);
        vm.expectRevert("PredictionMarketToken: only minter");
        token.mint(alice, 1 ether);
    }

    function testOnlyMinterCanBurn() public {
        token.mint(alice, 50 ether);

        vm.prank(alice);
        vm.expectRevert("PredictionMarketToken: only minter");
        token.burn(alice, 10 ether);
    }

    function testMinterCanChangeMinter() public {
        token.setMinter(alice);
        assertEq(token.minter(), alice);

        vm.prank(alice);
        token.mint(bob, 10 ether);
        assertEq(token.balanceOf(bob), 10 ether);
    }
}
