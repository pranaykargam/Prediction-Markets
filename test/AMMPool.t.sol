
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictionMarketToken.sol";
import "../src/FifaAMMPool.sol";

contract AMMPoolTest is Test {
    PredictionMarketToken usdc;
    PredictionMarketToken yes;
    PredictionMarketToken no;
    AMMPool pool;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        usdc = new PredictionMarketToken("USD Coin", "USDC", address(this));
        yes = new PredictionMarketToken("YES Token", "YES", address(this));
        no = new PredictionMarketToken("NO Token", "NO", address(this));

        pool = new AMMPool(address(usdc), address(yes), address(no), address(this), 30);
    }

    function testAddAndRemoveLiquidity() public {
        usdc.mint(address(this), 1_000 ether);
        usdc.transfer(address(pool), 1_000 ether);
        yes.mint(address(pool), 500 ether);
        no.mint(address(pool), 500 ether);

        pool.addLiquidity(address(this), 1_000 ether, 500 ether, 500 ether);
        uint256 shares = pool.lpShares(address(this));
        assertGt(shares, 0);

        pool.removeLiquidity(address(this), shares);
        assertEq(usdc.balanceOf(address(this)), 1_000 ether);
        assertEq(yes.balanceOf(address(this)), 500 ether);
        assertEq(no.balanceOf(address(this)), 500 ether);
    }

    function testSwapUsdcForYesAndBack() public {
        usdc.mint(address(this), 1_000 ether);
        usdc.transfer(address(pool), 1_000 ether);
        yes.mint(address(pool), 1_000 ether);
        no.mint(address(pool), 1_000 ether);

        pool.addLiquidity(address(this), 1_000 ether, 1_000 ether, 1_000 ether);

        pool.swapUsdcForYes(100 ether, 1, alice);
        assertGt(yes.balanceOf(alice), 0);

        yes.mint(address(pool), 100 ether);
        pool.swapYesForUsdc(10 ether, 1, bob);
        assertGt(usdc.balanceOf(bob), 0);
    }

    function testSwapUsdcForNoAndBack() public {
        usdc.mint(address(this), 1_000 ether);
        usdc.transfer(address(pool), 1_000 ether);
        yes.mint(address(pool), 1_000 ether);
        no.mint(address(pool), 1_000 ether);

        pool.addLiquidity(address(this), 1_000 ether, 1_000 ether, 1_000 ether);

        pool.swapUsdcForNo(100 ether, 1, alice);
        assertGt(no.balanceOf(alice), 0);

        no.mint(address(pool), 100 ether);
        pool.swapNoForUsdc(10 ether, 1, bob);
        assertGt(usdc.balanceOf(bob), 0);
    }

    function testOnlyMarketCanCallPoolMethods() public {
        vm.prank(alice);
        vm.expectRevert("AMMPool: only market");
        pool.addLiquidity(alice, 1 ether, 1 ether, 1 ether);
    }
}
