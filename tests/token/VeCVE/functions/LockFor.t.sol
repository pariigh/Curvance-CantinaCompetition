// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseVeCVE } from "../TestBaseVeCVE.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { VeCVE } from "contracts/token/VeCVE.sol";

contract LockForTest is TestBaseVeCVE {
    event Locked(address indexed user, uint256 amount);

    function test_lockFor_fail_whenVeCVEShutdown(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        veCVE.shutdown();

        vm.expectRevert(VeCVE.VeCVE_VeCVEShutdown.selector);
        veCVE.lockFor(
            address(1),
            100,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_fail_whenAmountIsZero(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.lockFor(address(1), 0, true, address(this), rewardsData, "", 0);
    }

    function test_lockFor_fail_whenLockerIsNotApproved(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        vm.expectRevert(VeCVE.VeCVE_InvalidLock.selector);
        veCVE.lockFor(
            address(1),
            100,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_fail_whenBalanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.lockFor(
            address(1),
            100,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_fail_whenAllowanceIsNotEnough(
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        veCVE.lockFor(
            address(1),
            100,
            true,
            address(this),
            rewardsData,
            "",
            0
        );
    }

    function test_lockFor_success_withContinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        vm.assume(amount > 0 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(1), amount);

        veCVE.lockFor(
            address(1),
            amount,
            true,
            address(this),
            rewardsData,
            "",
            0
        );

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(address(1)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);

        assertEq(
            veCVE.chainTokenPoints(),
            (amount * veCVE.clPointMultiplier()) / veCVE.DENOMINATOR()
        );
        assertEq(
            veCVE.userTokenPoints(address(1)),
            (amount * veCVE.clPointMultiplier()) / veCVE.DENOMINATOR()
        );
        assertEq(veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)), 0);
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(1),
                veCVE.currentEpoch(unlockTime)
            ),
            0
        );
    }

    function test_lockFor_success_withDiscontinuousLock_fuzzed(
        uint256 amount,
        bool shouldLock,
        bool isFreshLock,
        bool isFreshLockContinuous
    ) public setRewardsData(shouldLock, isFreshLock, isFreshLockContinuous) {
        centralRegistry.addVeCVELocker(address(this));

        deal(address(cve), address(this), 100e18);
        cve.approve(address(veCVE), 100e18);

        vm.assume(amount > 0 && amount <= 100e18);

        vm.expectEmit(true, true, true, true, address(veCVE));
        emit Locked(address(1), amount);

        veCVE.lockFor(
            address(1),
            amount,
            false,
            address(this),
            rewardsData,
            "",
            0
        );

        assertEq(cve.balanceOf(address(this)), 100e18 - amount);
        assertEq(veCVE.balanceOf(address(1)), amount);

        (, uint40 unlockTime) = veCVE.userLocks(address(1), 0);

        assertEq(veCVE.chainTokenPoints(), amount);
        assertEq(veCVE.userTokenPoints(address(1)), amount);
        assertEq(
            veCVE.chainUnlocksByEpoch(veCVE.currentEpoch(unlockTime)),
            amount
        );
        assertEq(
            veCVE.userTokenUnlocksByEpoch(
                address(1),
                veCVE.currentEpoch(unlockTime)
            ),
            amount
        );
    }
}