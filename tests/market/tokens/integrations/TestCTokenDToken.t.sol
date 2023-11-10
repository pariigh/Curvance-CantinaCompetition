// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "tests/market/TestBaseMarket.sol";

contract TestCTokenDToken is TestBaseMarket {
    receive() external payable {}

    fallback() external payable {}

    function setUp() public override {
        super.setUp();

        // prepare 200K USDC
        _prepareUSDC(user1, 200000e6);
        _prepareUSDC(user2, 200000e6);
        _prepareUSDC(liquidator, 200000e6);

        // prepare 1 BAL-RETH/WETH
        _prepareBALRETH(user1, 1 ether);
        _prepareBALRETH(user2, 1 ether);
        _prepareBALRETH(liquidator, 1 ether);
    }

    function testInitialize() public {
        assertEq(dUSDC.decimals(), 6);
        assertEq(cBALRETH.decimals(), 18);
    }

    // function testMint() public {
    //     cDAI = new CErc20(
    //         DAI_ADDRESS,
    //         ILendtroller(lendtroller),
    //         InterestRateModel(address(deployments.jumpRateModel())),
    //         _ONE,
    //         "cDAI",
    //         "cDAI",
    //         18,
    //         payable(admin)
    //     );
    //     cETH = new CEther(
    //         ILendtroller(lendtroller),
    //         InterestRateModel(address(deployments.jumpRateModel())),
    //         _ONE,
    //         "cETH",
    //         "cETH",
    //         18,
    //         payable(admin)
    //     );
    //     // support market
    //     vm.prank(admin);
    //     Lendtroller(lendtroller)._supportMarket(CToken(address(cDAI)));
    //     vm.prank(admin);
    //     Lendtroller(lendtroller)._supportMarket(CToken(address(cETH)));

    //     // user1 enter markets
    //     vm.prank(user1);
    //     address[] memory markets = new address[](2);
    //     markets[0] = address(cDAI);
    //     markets[1] = address(cETH);
    //     ILendtroller(lendtroller).enterMarkets(markets);

    //     // user1 approve
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertGt(cDAI.balanceOf(user1), 0);

    //     // user2 enter market
    //     vm.prank(user2);
    //     ILendtroller(lendtroller).enterMarkets(markets);

    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertGt(cETH.balanceOf(user2), 0);
    // }

    // function testRedeem() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // auser1 pprove
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     uint256 balanceBeforeMint = dai.balanceOf(user1);
    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertGt(balanceBeforeMint, dai.balanceOf(user1));

    //     // user1 redeem
    //     vm.prank(user1);
    //     cDAI.redeem(100e18);
    //     assertEq(cDAI.balanceOf(user1), 0);
    //     assertEq(balanceBeforeMint, dai.balanceOf(user1));

    //     // user2 enter markets
    //     _enterMarkets(user2);

    //     balanceBeforeMint = user2.balance;
    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user2), 100e18);
    //     assertGt(balanceBeforeMint, user2.balance);

    //     // user2 redeem
    //     vm.prank(user2);
    //     cETH.redeem(100e18);
    //     assertEq(cETH.balanceOf(user2), 0);
    //     assertEq(balanceBeforeMint, user2.balance);
    // }

    // function testRedeemUnderlying() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // user1 approve
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     uint256 balanceBeforeMint = dai.balanceOf(user1);
    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertGt(balanceBeforeMint, dai.balanceOf(user1));

    //     // redeem
    //     vm.prank(user1);
    //     cDAI.redeemUnderlying(100e18);
    //     assertEq(cDAI.balanceOf(user1), 0);
    //     assertEq(balanceBeforeMint, dai.balanceOf(user1));

    //     // user2 enter markets
    //     _enterMarkets(user2);

    //     balanceBeforeMint = user2.balance;
    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user2), 100e18);
    //     assertGt(balanceBeforeMint, user2.balance);

    //     // user2 redeem
    //     vm.prank(user2);
    //     cETH.redeemUnderlying(100e18);
    //     assertEq(cETH.balanceOf(user2), 0);
    //     assertEq(balanceBeforeMint, user2.balance);
    // }

    // function testBorrow() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // user1 approve
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);

    //     // user2 enter markets
    //     _enterMarkets(user2);

    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user2), 100e18);

    //     // user2 borrow
    //     uint256 balanceBeforeBorrow = dai.balanceOf(user2);
    //     vm.prank(user2);
    //     cDAI.borrow(100e18);
    //     assertEq(cETH.balanceOf(user2), 100e18);
    //     assertEq(balanceBeforeBorrow + 100e18, dai.balanceOf(user2));

    //     // user1 borrow
    //     balanceBeforeBorrow = user1.balance;
    //     vm.prank(user1);
    //     cETH.borrow(25e18);
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertEq(balanceBeforeBorrow + 25e18, user1.balance);
    // }

    // function testBorrow2() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // user1 approve
    //     dai.approve(address(cDAI), 100e18);

    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);

    //     // user1 enter markets
    //     _enterMarkets(user1);

    //     // user1 mint
    //     vm.prank(user1);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user1), 100e18);

    //     // user1 borrow
    //     uint256 balanceBeforeBorrow = dai.balanceOf(user1);
    //     vm.prank(user1);
    //     cDAI.borrow(100e18);
    //     assertEq(cETH.balanceOf(user1), 100e18);
    //     assertEq(balanceBeforeBorrow + 100e18, dai.balanceOf(user1));

    //     // user1 borrow
    //     balanceBeforeBorrow = user1.balance;
    //     vm.prank(user1);
    //     cETH.borrow(25e18);
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertEq(balanceBeforeBorrow + 25e18, user1.balance);
    // }

    // function testRepayBorrowBehalf() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // user1 approve
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);

    //     // user2 enter markets
    //     _enterMarkets(user2);

    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user2), 100e18);

    //     // user2 borrow
    //     uint256 balanceBeforeBorrowUser2 = dai.balanceOf(user2);
    //     vm.prank(user2);
    //     cDAI.borrow(100e18);
    //     assertEq(cETH.balanceOf(user2), 100e18);
    //     assertEq(balanceBeforeBorrowUser2 + 100e18, dai.balanceOf(user2));

    //     // user1 borrow
    //     uint256 balanceBeforeBorrowUser1 = user1.balance;
    //     vm.prank(user1);
    //     cETH.borrow(25e18);
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertEq(balanceBeforeBorrowUser1 + 25e18, user1.balance);

    //     // user2 approve
    //     vm.prank(user2);
    //     dai.approve(address(cDAI), 100e18);

    //     // user2 repay
    //     vm.prank(user2);
    //     cDAI.repayBorrowBehalf(user2, 100e18);
    //     assertEq(balanceBeforeBorrowUser2, dai.balanceOf(user2));

    //     // user1 repay
    //     vm.prank(user1);
    //     cETH.repayBorrowBehalf{ value: 25e18 }(user1);
    //     assertEq(balanceBeforeBorrowUser1, user1.balance);
    // }

    // function testLiquidateBorrow() public {
    //     _deployCDAI();
    //     _deployCEther();

    //     _setupCDAIMarket();
    //     _setupCEtherMarket();

    //     _enterMarkets(user1);

    //     // user1 approve
    //     vm.prank(user1);
    //     dai.approve(address(cDAI), 100e18);

    //     // user1 mint
    //     vm.prank(user1);
    //     assertTrue(cDAI.mint(100e18));
    //     assertEq(cDAI.balanceOf(user1), 100e18);

    //     // user2 enter markets
    //     _enterMarkets(user2);

    //     // user2 mint
    //     vm.prank(user2);
    //     cETH.mint{ value: 100e18 }();
    //     assertEq(cETH.balanceOf(user2), 100e18);

    //     // user2 borrow
    //     uint256 balanceBeforeBorrowUser2 = dai.balanceOf(user2);
    //     vm.prank(user2);
    //     cDAI.borrow(100e18);
    //     assertEq(cETH.balanceOf(user2), 100e18);
    //     assertEq(balanceBeforeBorrowUser2 + 100e18, dai.balanceOf(user2));

    //     // user1 borrow
    //     uint256 balanceBeforeBorrowUser1 = user1.balance;
    //     vm.prank(user1);
    //     cETH.borrow(25e18);
    //     assertEq(cDAI.balanceOf(user1), 100e18);
    //     assertEq(balanceBeforeBorrowUser1 + 25e18, user1.balance);

    //     // set collateral factor
    //     vm.prank(admin);
    //     Lendtroller(lendtroller)._setCollateralFactor(
    //         CToken(address(cDAI)),
    //         4e17
    //     );
    //     vm.prank(admin);
    //     Lendtroller(lendtroller)._setCollateralFactor(
    //         CToken(address(cETH)),
    //         4e17
    //     );

    //     // liquidator approve
    //     vm.prank(liquidator);
    //     dai.approve(address(cDAI), 100e18);

    //     // liquidator liquidateBorrow user2
    //     vm.prank(liquidator);
    //     cDAI.liquidateBorrow(user2, 24e18, ICToken(cETH));

    //     assertEq(cETH.balanceOf(liquidator), 5832000000000000000);

    //     // liquidator liquidateBorrow user1
    //     vm.prank(liquidator);
    //     cETH.liquidateBorrow{ value: 6e18 }(user1, CToken(cDAI));

    //     assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);
    // }
}