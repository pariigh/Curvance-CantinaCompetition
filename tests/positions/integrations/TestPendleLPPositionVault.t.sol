// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { ERC20 } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IUniswapV3Router } from "contracts/interfaces/external/uniswap/IUniswapV3Router.sol";
import { IPendleRouter, ApproxParams } from "contracts/interfaces/external/pendle/IPendleRouter.sol";
import { PendleLPPositionVault } from "contracts/deposits/adaptors/PendleLPPositionVault.sol";
import { CToken } from "contracts/market/collateral/CToken.sol";

import "tests/market/TestBaseMarket.sol";

contract TestPendleLPPositionVault is TestBaseMarket {
    address private _UNISWAP_V3_SWAP_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    IPendleRouter private _ROUTER =
        IPendleRouter(0x0000000001E4ef00d069e71d6bA041b0A16F7eA0);
    address private _STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private _PT_STETH = 0x7758896b6AC966BbABcf143eFA963030f17D3EdF; // PT-stETH-26DEC24
    address private _PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    ERC20 private _LP_STETH =
        ERC20(0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2); // PT-stETH-26DEC24/SY-stETH Market

    PendleLPPositionVault positionVault;
    CToken public cSTETH;

    /*
    LP token address	0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4
    Deposit contract address	0xF403C135812408BFbE8713b5A23a04b3D48AAE31
    Rewards contract address	0xb05262D4aaAA38D0Af4AaB244D446ebDb5afd4A7
    Convex pool id	188
    Convex pool url	https://www.convexfinance.com/stake/ethereum/188
    */

    receive() external payable {}

    fallback() external payable {}

    // this is to use address(this) as mock CToken address
    function tokenType() external pure returns (uint256) {
        return 1;
    }

    function setUp() public override {
        _fork();

        _deployCentralRegistry();
        _deployGaugePool();
        _deployLendtroller();

        centralRegistry.addHarvester(address(this));
        centralRegistry.setFeeAccumulator(address(this));

        positionVault = new PendleLPPositionVault(
            _LP_STETH,
            ICentralRegistry(address(centralRegistry)),
            _ROUTER
        );

        cSTETH = new CToken(
            ICentralRegistry(address(centralRegistry)),
            address(_LP_STETH),
            address(lendtroller),
            address(positionVault)
        );
        positionVault.initiateVault(address(cSTETH));

        centralRegistry.addSwapper(_UNISWAP_V3_SWAP_ROUTER);
    }

    function testPendleStethLP() public {
        uint256 assets = 100e18;
        deal(address(_LP_STETH), address(cSTETH), assets);

        vm.prank(address(cSTETH));
        _LP_STETH.approve(address(positionVault), assets);

        vm.prank(address(cSTETH));
        positionVault.deposit(assets, address(this));

        assertEq(
            positionVault.totalAssets(),
            assets,
            "Total Assets should equal user deposit."
        );

        // Advance time to earn CRV and CVX rewards
        vm.warp(block.timestamp + 3 days);

        // Mint some extra rewards for Vault.
        deal(address(_PENDLE), address(positionVault), 100e18);

        uint256 rewardAmount = (100e18 * 84) / 100; // 16% for protocol harvest fee;
        SwapperLib.Swap[] memory swaps = new SwapperLib.Swap[](1);
        swaps[0].inputToken = _PENDLE;
        swaps[0].inputAmount = rewardAmount;
        swaps[0].outputToken = _WETH_ADDRESS;
        swaps[0].target = _UNISWAP_V3_SWAP_ROUTER;
        IUniswapV3Router.ExactInputSingleParams memory params;
        params.tokenIn = _PENDLE;
        params.tokenOut = _WETH_ADDRESS;
        params.fee = 3000;
        params.recipient = address(positionVault);
        params.deadline = block.timestamp;
        params.amountIn = rewardAmount;
        params.amountOutMinimum = 0;
        params.sqrtPriceLimitX96 = 0;
        swaps[0].call = abi.encodeWithSelector(
            IUniswapV3Router.exactInputSingle.selector,
            params
        );

        ApproxParams memory approx;
        approx.guessMin = 1e10;
        approx.guessMax = 1e18;
        approx.guessOffchain = 0;
        approx.maxIteration = 200;
        approx.eps = 1e18;

        positionVault.harvest(abi.encode(swaps, 0, approx));

        vm.warp(block.timestamp + 8 days);

        uint256 totalAssets = positionVault.totalAssets();
        assertGt(
            totalAssets,
            assets,
            "Total Assets should equal user deposit."
        );

        vm.prank(address(cSTETH));
        positionVault.withdraw(totalAssets, address(this), address(this));
    }
}