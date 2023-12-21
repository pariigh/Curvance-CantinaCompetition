// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBaseMarket } from "tests/market/TestBaseMarket.sol";
import { CentralRegistry } from "contracts/architecture/CentralRegistry.sol";

contract Market {
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        if (interfaceId == 0xffffffff) {
            return false;
        }
        return true;
    }
}

contract AddLendingMarketTest is TestBaseMarket {
    address newMarket;

    event NewCurvanceContract(string indexed contractType, address newAddress);

    function setUp() public virtual override {
        super.setUp();
        newMarket = address(new Market());
    }

    function test_addLendingMarket_fail_whenUnauthorized() public {
        vm.startPrank(address(0));
        vm.expectRevert(CentralRegistry.CentralRegistry__Unauthorized.selector);
        centralRegistry.addLendingMarket(newMarket, 5000);
        vm.stopPrank();
    }

    function test_addLendingMarket_fail_whenMarketAlreadyAdded() public {
        centralRegistry.addLendingMarket(newMarket, 5000);
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.addLendingMarket(newMarket, 5000);
    }

    function test_addLendingMarket_fail_whenNoSupportForERC165() public {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.addLendingMarket(user1, 5000);
    }

    function test_addLendingMarket_fail_whenFeeTooHigh() public {
        vm.expectRevert(
            CentralRegistry.CentralRegistry__ParametersMisconfigured.selector
        );
        centralRegistry.addLendingMarket(newMarket, 5001);
    }

    function test_addLendingMarket_success() public {
        assertFalse(centralRegistry.isLendingMarket(newMarket));

        vm.expectEmit(true, true, true, true);
        emit NewCurvanceContract("Lending Market", newMarket);
        centralRegistry.addLendingMarket(newMarket, 5000);

        assertTrue(centralRegistry.isLendingMarket(newMarket));
        assertEq(
            centralRegistry.protocolInterestFactor(newMarket),
            5000 * 1e14
        );
    }
}