// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import { BasePositionVault, ERC4626, SafeTransferLib, ERC20, Math, PriceRouter } from "./BasePositionVault.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

// External interfaces
import { IVeloGauge } from "contracts/interfaces/external/velodrome/IVeloGauge.sol";
import { IVeloRouter } from "contracts/interfaces/external/velodrome/IVeloRouter.sol";
import { IVeloPair } from "contracts/interfaces/external/velodrome/IVeloPair.sol";
import { IVeloPairFactory } from "contracts/interfaces/external/velodrome/IVeloPairFactory.sol";
import { IOptiSwap } from "contracts/interfaces/external/velodrome/IOptiSwap.sol";
import { IOptiSwapPair } from "contracts/interfaces/external/velodrome/IOptiSwapPair.sol";

// Chainlink interfaces
import { KeeperCompatibleInterface } from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { IChainlinkAggregator } from "contracts/interfaces/external/chainlink/IChainlinkAggregator.sol";

contract VelodromeStablePositionVault is BasePositionVault {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             GLOBAL STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Velodrome Gauge contract.
    IVeloGauge private gauge;

    /// @notice Velodrome Router contract.
    IVeloPairFactory private pairFactory;

    /// @notice Velodrome Router contract.
    IVeloRouter private router;

    /// @notice Velodrome Router contract.
    address private optiSwap;

    /// @notice Reward token addresses.
    address[] private rewards;

    /// @notice tokenA address
    address private tokenA;

    /// @notice tokenB address
    address private tokenB;

    /// @notice tokenA decimals
    uint256 private decimalsA;

    /// @notice tokenB decimals
    uint256 private decimalsB;

    /// @notice Mainnet token contracts important for this vault.
    ERC20 private constant WETH =
        ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant VELO =
        ERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);

    // Owner needs to be able to set swap paths, deposit data, fee, fee accumulator
    /// @notice Value out from harvest swaps must be greater than
    ///         value in * 1 - (harvestSlippage + upkeepFee);
    uint64 public harvestSlippage = 0.01e18;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event HarvestSlippageChanged(uint64 slippage);
    event Harvest(uint256 yield);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error VelodromePositionVault__BadSlippage();
    error VelodromePositionVault__WatchdogNotSet();

    /*//////////////////////////////////////////////////////////////
                              SETUP LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Vaults are designed to be deployed using Minimal Proxy Contracts,
    ///         but they can be deployed normally,
    ///         but `initialize` must ALWAYS be called either way.
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        ICentralRegistry _centralRegistry
    ) BasePositionVault(_asset, _name, _symbol, _decimals, _centralRegistry) {}

    /// @notice Initialize function to fully setup this vault.
    function initialize(
        ERC20 _asset,
        ICentralRegistry _centralRegistry,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        BasePositionVault.PositionVaultMetaData calldata _metaData,
        bytes memory _initializeData
    ) public override initializer {
        super.initialize(
            _asset,
            _centralRegistry,
            _name,
            _symbol,
            _decimals,
            _metaData,
            _initializeData
        );
        (
            address _tokenA,
            address _tokenB,
            address[] memory _rewards,
            IVeloGauge _gauge,
            IVeloRouter _router,
            IVeloPairFactory _pairFactory,
            address _optiSwap
        ) = abi.decode(
                _initializeData,
                (
                    address,
                    address,
                    address[],
                    IVeloGauge,
                    IVeloRouter,
                    IVeloPairFactory,
                    address
                )
            );
        tokenA = _tokenA;
        tokenB = _tokenB;
        decimalsA = 10 ** ERC20(_tokenA).decimals();
        decimalsB = 10 ** ERC20(_tokenB).decimals();
        gauge = _gauge;
        router = _router;
        pairFactory = _pairFactory;
        optiSwap = _optiSwap;

        uint256 numRewards = _rewards.length;

        for (uint256 i = 0; i < numRewards; ++i) {
            rewards.push(_rewards[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER LOGIC
    //////////////////////////////////////////////////////////////*/

    function updateHarvestSlippage(uint64 _slippage) external onlyDaoManager {
        harvestSlippage = _slippage;
        emit HarvestSlippageChanged(_slippage);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest(
        bytes memory
    ) public override whenNotShutdown nonReentrant returns (uint256 yield) {
        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // We need to claim vested rewards.
            _vestRewards(_totalAssets + pending);
        }

        // Can only harvest once previous reward period is done.
        if (
            positionVaultAccounting._lastVestClaim >=
            positionVaultAccounting._vestingPeriodEnd
        ) {
            {
                // 1. Withdraw all the rewards.
                gauge.getReward(address(this), rewards);
            }

            uint256 valueIn;
            {
                // 2. Convert rewards to ETH
                uint256 rewardTokenCount = rewards.length;
                address reward;
                uint256 amount;
                uint256 protocolFee;
                uint256 rewardPrice;

                for (uint256 i = 0; i < rewardTokenCount; ++i) {
                    reward = rewards[i];
                    amount = ERC20(reward).balanceOf(address(this));
                    if (amount == 0) continue;

                    // Take platform fee
                    protocolFee = amount.mulDivDown(
                        positionVaultMetaData.platformFee,
                        1e18
                    );
                    amount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        reward,
                        positionVaultMetaData.feeAccumulator,
                        protocolFee
                    );
                    (rewardPrice, ) = positionVaultMetaData
                        .priceRouter
                        .getPrice(reward, true, true);

                    valueIn += amount.mulDivDown(
                        rewardPrice,
                        10 ** ERC20(reward).decimals()
                    );

                    if (reward == tokenA) continue;

                    optiSwapExactTokensForTokens(reward, tokenA, amount);
                }
            }

            uint256 totalAmountA;
            uint256 totalAmountB;
            {
                // 3. Convert tokenA to LP Token underlyings
                totalAmountA = ERC20(tokenA).balanceOf(address(this));
                if (totalAmountA == 0)
                    revert VelodromePositionVault__BadSlippage();

                if (totalAmountA > 0) {
                    uint256 feeForUpkeep = totalAmountA.mulDivDown(
                        positionVaultMetaData.upkeepFee,
                        1e18
                    );
                    if (positionVaultMetaData.positionWatchdog == address(0))
                        revert VelodromePositionVault__WatchdogNotSet();
                    SafeTransferLib.safeTransfer(
                        tokenA,
                        positionVaultMetaData.positionWatchdog,
                        feeForUpkeep
                    );
                    totalAmountA -= feeForUpkeep;
                }

                (uint256 r0, uint256 r1, ) = IVeloPair(asset()).getReserves();
                (uint256 reserveA, uint256 reserveB) = tokenA ==
                    IVeloPair(asset()).token0()
                    ? (r0, r1)
                    : (r1, r0);
                uint256 swapAmount = _optimalDeposit(
                    totalAmountA,
                    reserveA,
                    reserveB,
                    decimalsA,
                    decimalsB
                );
                swapExactTokensForTokens(tokenA, tokenB, swapAmount);

                totalAmountA -= swapAmount;
                totalAmountB = ERC20(tokenB).balanceOf(address(this));
            }

            uint256 valueOut;
            {
                // 4. Check USD value slippage

                (uint256 tokenAPrice, ) = positionVaultMetaData
                    .priceRouter
                    .getPrice(tokenA, true, true);
                (uint256 tokenBPrice, ) = positionVaultMetaData
                    .priceRouter
                    .getPrice(tokenB, true, true);
                valueOut =
                    totalAmountA.mulDivDown(
                        tokenAPrice,
                        10 ** ERC20(tokenA).decimals()
                    ) +
                    totalAmountB.mulDivDown(
                        tokenBPrice,
                        10 ** ERC20(tokenB).decimals()
                    );

                // Compare value in vs value out.
                if (
                    valueOut <
                    valueIn.mulDivDown(
                        1e18 -
                            (positionVaultMetaData.upkeepFee +
                                harvestSlippage),
                        1e18
                    )
                ) revert VelodromePositionVault__BadSlippage();
            }

            {
                // 5. Deposit into Velodrome
                yield = addLiquidity(
                    tokenA,
                    tokenB,
                    totalAmountA,
                    totalAmountB
                );
            }

            {
                // 6. Deposit into Gauge
                _deposit(yield);
            }

            // Update Vesting info.
            positionVaultAccounting._rewardRate = uint128(
                yield.mulDivDown(REWARD_SCALER, REWARD_PERIOD)
            );
            positionVaultAccounting._vestingPeriodEnd =
                uint64(block.timestamp) +
                REWARD_PERIOD;
            positionVaultAccounting._lastVestClaim = uint64(block.timestamp);
            emit Harvest(yield);
        } // else yield is zero.
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 assets) internal override {
        gauge.withdraw(assets);
    }

    function _deposit(uint256 assets) internal override {
        SafeTransferLib.safeApprove(asset(), address(gauge), assets);
        gauge.deposit(assets, 0);
    }

    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return gauge.balanceOf(address(this));
    }

    function _optimalDeposit(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _decimalsA,
        uint256 _decimalsB
    ) internal pure returns (uint256) {
        uint256 num;
        uint256 den;

        {
            uint256 a = (_amountA * 1e18) / _decimalsA;
            uint256 x = (_reserveA * 1e18) / _decimalsA;
            uint256 y = (_reserveB * 1e18) / _decimalsB;
            uint256 x2 = (x * x) / 1e18;
            uint256 y2 = (y * y) / 1e18;
            uint256 p = (y * (((x2 * 3 + y2) * 1e18) / (y2 * 3 + x2))) / x;
            num = a * y;
            den = ((a + x) * p) / 1e18 + y;
        }

        return ((num / den) * _decimalsA) / 1e18;
    }

    function approveRouter(address token, uint256 amount) internal {
        if (ERC20(token).allowance(address(this), address(router)) >= amount)
            return;
        SafeTransferLib.safeApprove(token, address(router), type(uint256).max);
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal {
        approveRouter(tokenIn, amount);
        IVeloRouter(router).swapExactTokensForTokensSimple(
            amount,
            0,
            tokenIn,
            tokenOut,
            true,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB
    ) internal returns (uint256 liquidity) {
        approveRouter(_tokenA, _amountA);
        approveRouter(_tokenB, _amountB);
        (, , liquidity) = IVeloRouter(router).addLiquidity(
            _tokenA,
            _tokenB,
            true,
            _amountA,
            _amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForBestAmountOut(
        IOptiSwap _optiSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            return amountIn;
        }
        address pair;
        (pair, amountOut) = _optiSwap.getBestAmountOut(
            amountIn,
            tokenIn,
            tokenOut
        );
        require(pair != address(0), "NO_PAIR");
        SafeTransferLib.safeTransfer(tokenIn, pair, amountIn);
        if (tokenIn < tokenOut) {
            IOptiSwapPair(pair).swap(
                0,
                amountOut,
                address(this),
                new bytes(0)
            );
        } else {
            IOptiSwapPair(pair).swap(
                amountOut,
                0,
                address(this),
                new bytes(0)
            );
        }
    }

    function optiSwapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            return amountIn;
        }
        IOptiSwap _optiSwap = IOptiSwap(optiSwap);
        address nextHop = _optiSwap.getBridgeToken(tokenIn);
        if (nextHop == tokenOut) {
            return
                swapTokensForBestAmountOut(
                    _optiSwap,
                    tokenIn,
                    tokenOut,
                    amountIn
                );
        }
        address waypoint = _optiSwap.getBridgeToken(tokenOut);
        if (tokenIn == waypoint) {
            return
                swapTokensForBestAmountOut(
                    _optiSwap,
                    tokenIn,
                    tokenOut,
                    amountIn
                );
        }
        uint256 hopAmountOut;
        if (nextHop != tokenIn) {
            hopAmountOut = swapTokensForBestAmountOut(
                _optiSwap,
                tokenIn,
                nextHop,
                amountIn
            );
        } else {
            hopAmountOut = amountIn;
        }
        if (nextHop == waypoint) {
            return
                swapTokensForBestAmountOut(
                    _optiSwap,
                    nextHop,
                    tokenOut,
                    hopAmountOut
                );
        } else if (waypoint == tokenOut) {
            return
                optiSwapExactTokensForTokens(nextHop, tokenOut, hopAmountOut);
        } else {
            uint256 waypointAmountOut = optiSwapExactTokensForTokens(
                nextHop,
                waypoint,
                hopAmountOut
            );
            return
                swapTokensForBestAmountOut(
                    _optiSwap,
                    waypoint,
                    tokenOut,
                    waypointAmountOut
                );
        }
    }
}