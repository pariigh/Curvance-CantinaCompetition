// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseLendtroller } from "../TestBaseLendtroller.sol";
import { Lendtroller } from "contracts/market/lendtroller/Lendtroller.sol";
import { IMToken } from "contracts/interfaces/market/IMToken.sol";

contract CanBorrowWithNotifyTest is TestBaseLendtroller {
    event MarketEntered(address mToken, address account);

    function setUp() public override {
        super.setUp();

        lendtroller.listMarketToken(address(dUSDC));
    }

    function test_canBorrowWithNotify_fail_whenCallerIsNotMToken() public {
        vm.expectRevert(Lendtroller.Lendtroller__AddressUnauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenCallerMTokenIsNotListed()
        public
    {
        vm.prank(address(dDAI));

        vm.expectRevert(Lendtroller.Lendtroller__TokenNotListed.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenBorrowPaused() public {
        lendtroller.setBorrowPaused(IMToken(address(dUSDC)), true);

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__Paused.selector);
        lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenMTokenIsNotListed() public {
        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__AddressUnauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    function test_canBorrowWithNotify_fail_whenCallerIsNotMTokenAndBorrowerNotInMarket()
        public
    {
        lendtroller.listMarketToken(address(dDAI));

        vm.prank(address(dUSDC));

        vm.expectRevert(Lendtroller.Lendtroller__AddressUnauthorized.selector);
        lendtroller.canBorrowWithNotify(address(dDAI), user1, 100e6);
    }

    // function test_canBorrowWithNotify_fail_whenExceedsBorrowCaps() public {
    //     IMToken[] memory mTokens = new IMToken[](1);
    //     uint256[] memory borrowCaps = new uint256[](1);
    //     mTokens[0] = IMToken(address(dUSDC));
    //     borrowCaps[0] = 100e6 - 1;

    //     lendtroller.setCTokenCollateralCaps(mTokens, borrowCaps);

    //     vm.prank(address(dUSDC));

    //     vm.expectRevert(Lendtroller.Lendtroller__BorrowCapReached.selector);
    //     lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);
    // }

    // function test_canBorrowWithNotify_success() public {
    //     vm.expectEmit(true, true, true, true, address(lendtroller));
    //     emit MarketEntered(address(dUSDC), user1);

    //     vm.prank(address(dUSDC));
    //     lendtroller.canBorrowWithNotify(address(dUSDC), user1, 100e6);

    //     assertEq(lendtroller.accountAssets(user1), block.timestamp);
    //     assertTrue(lendtroller.getAccountMembership(address(dUSDC), user1));
    // }
}