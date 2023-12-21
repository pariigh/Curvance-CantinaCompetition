// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BasePositionVault, SafeTransferLib, ERC20, Math, ICentralRegistry } from "contracts/deposits/adaptors/BasePositionVault.sol";
import { SwapperLib } from "contracts/libraries/SwapperLib.sol";
import { CommonLib } from "contracts/market/zapper/protocols/CommonLib.sol";

import { IBooster } from "contracts/interfaces/external/convex/IBooster.sol";
import { IBaseRewardPool } from "contracts/interfaces/external/convex/IBaseRewardPool.sol";
import { IRewards } from "contracts/interfaces/external/convex/IRewards.sol";
import { ICurveFi } from "contracts/interfaces/external/curve/ICurveFi.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract ConvexPositionVault is BasePositionVault {
    using Math for uint256;

    /// TYPES ///

    struct StrategyData {
        ICurveFi curvePool; // Curve Pool Address
        uint256 pid; // Convex Pool Id
        IBaseRewardPool rewarder; // Convex Rewarder contract
        IBooster booster; // Convex Booster contract
        address[] rewardTokens; // Convex reward assets
        address[] underlyingTokens; // Curve LP underlying assets
    }

    /// CONSTANTS ///

    address private constant _CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// STORAGE ///

    StrategyData public strategyData; // position vault packed configuration

    /// Token => underlying token of the Curve 4Pool LP or not
    mapping(address => bool) public isUnderlyingToken;

    /// EVENTS ///

    event Harvest(uint256 yield);

    /// ERRORS ///

    error ConvexPositionVault__UnsafePool();
    error ConvexPositionVault__InvalidVaultConfig();
    error ConvexPositionVault__InvalidCoinLength();
    error ConvexPositionVault__InvalidSwapper(
        uint256 index,
        address invalidSwapper
    );
    error ConvexPositionVault__NoYield();

    /// CONSTRUCTOR ///

    constructor(
        ERC20 asset_,
        ICentralRegistry centralRegistry_,
        uint256 pid_,
        address rewarder_,
        address booster_
    ) BasePositionVault(asset_, centralRegistry_) {
        // we only support Curves new ng pools with read only reentry protection
        if (pid_ <= 176) {
            revert ConvexPositionVault__UnsafePool();
        }

        strategyData.pid = pid_;
        strategyData.booster = IBooster(booster_);

        // query actual convex pool configuration data
        (address pidToken, , , address crvRewards, , bool shutdown) = IBooster(
            booster_
        ).poolInfo(strategyData.pid);

        // validate that the pool is still active and that the lp token
        // and rewarder in convex matches what we are configuring for
        if (
            pidToken != address(asset_) || shutdown || crvRewards != rewarder_
        ) {
            revert ConvexPositionVault__InvalidVaultConfig();
        }

        strategyData.curvePool = ICurveFi(pidToken);

        uint256 coinsLength;
        address token;

        // figure out how many tokens are in the curve pool
        while (true) {
            try ICurveFi(pidToken).coins(coinsLength) {
                ++coinsLength;
            } catch {
                break;
            }
        }

        // validate that the liquidity pool is actually a 4Pool
        if (coinsLength != 4) {
            revert ConvexPositionVault__InvalidCoinLength();
        }

        strategyData.rewarder = IBaseRewardPool(rewarder_);

        // add CRV as a reward token, then let convex tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = _CRV;
        uint256 extraRewardsLength = IBaseRewardPool(rewarder_)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            strategyData.rewardTokens.push() = IRewards(
                IBaseRewardPool(rewarder_).extraRewards(i)
            ).rewardToken();
        }

        // let curve lp tell you what its underlying tokens are
        strategyData.underlyingTokens = new address[](coinsLength);
        for (uint256 i; i < coinsLength; ) {
            token = ICurveFi(pidToken).coins(i);
            strategyData.underlyingTokens[i] = token;
            isUnderlyingToken[token] = true;

            unchecked {
                ++i;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    // PERMISSIONED FUNCTIONS

    function reQueryRewardTokens() external {
        delete strategyData.rewardTokens;

        // add CRV as a reward token, then let convex tell you what rewards
        // the vault will receive
        strategyData.rewardTokens.push() = _CRV;
        IBaseRewardPool rewarder = strategyData.rewarder;

        uint256 extraRewardsLength = rewarder.extraRewardsLength();
        for (uint256 i; i < extraRewardsLength; ++i) {
            strategyData.rewardTokens.push() = IRewards(
                rewarder.extraRewards(i)
            ).rewardToken();
        }
    }

    /// PUBLIC FUNCTIONS ///

    // REWARD AND HARVESTING LOGIC

    /// @notice Harvests and compounds outstanding vault rewards
    ///         and vests pending rewards
    /// @dev Only callable by Gelato Network bot
    /// @param data Bytes array for aggregator swap data
    /// @return yield The amount of new assets acquired from compounding vault yield
    function harvest(
        bytes calldata data
    ) external override onlyHarvestor returns (uint256 yield) {
        if (_vaultIsActive == 1) {
            _revert(VAULT_NOT_ACTIVE_SELECTOR);
        }

        uint256 pending = _calculatePendingRewards();
        if (pending > 0) {
            // claim vested rewards
            _vestRewards(_totalAssets + pending);
        }

        // can only harvest once previous reward period is done
        if (_checkVestStatus(_vaultData)) {
            // cache strategy data
            StrategyData memory sd = strategyData;

            // claim convex rewards
            sd.rewarder.getReward(address(this), true);

            (SwapperLib.Swap[] memory swapDataArray, uint256 minLPAmount) = abi
                .decode(data, (SwapperLib.Swap[], uint256));

            uint256 numRewardTokens = sd.rewardTokens.length;
            address rewardToken;
            uint256 rewardAmount;
            uint256 protocolFee;

            {
                // Cache Central registry values so we dont pay gas multiple times
                address feeAccumulator = centralRegistry.feeAccumulator();
                uint256 harvestFee = centralRegistry.protocolHarvestFee();

                for (uint256 i; i < numRewardTokens; ++i) {
                    rewardToken = sd.rewardTokens[i];
                    rewardAmount = ERC20(rewardToken).balanceOf(address(this));

                    if (rewardAmount == 0) {
                        continue;
                    }

                    // take protocol fee
                    protocolFee = rewardAmount.mulDivDown(harvestFee, 1e18);
                    rewardAmount -= protocolFee;
                    SafeTransferLib.safeTransfer(
                        address(rewardToken),
                        feeAccumulator,
                        protocolFee
                    );
                }
            }

            {
                uint256 numSwapData = swapDataArray.length;
                for (uint256 i; i < numSwapData; ++i) {
                    if (!centralRegistry.isSwapper(swapDataArray[i].target)) {
                        revert ConvexPositionVault__InvalidSwapper(
                            i,
                            swapDataArray[i].target
                        );
                    }
                    SwapperLib.swap(swapDataArray[i]);
                }
            }

            _addLiquidityToCurve(minLPAmount);

            // deposit assets into convex
            yield = ERC20(asset()).balanceOf(address(this));
            if (yield == 0) {
                revert ConvexPositionVault__NoYield();
            }
            _deposit(yield);

            // update vesting info
            // Cache vest period so we do not need to load it twice
            uint256 _vestPeriod = vestPeriod;
            _vaultData = _packVaultData(
                yield.mulDivDown(WAD, _vestPeriod),
                block.timestamp + _vestPeriod
            );

            emit Harvest(yield);
        }
        // else yield is zero
    }

    /// INTERNAL FUNCTIONS ///

    // INTERNAL POSITION LOGIC

    /// @notice Deposits specified amount of assets into Convex booster contract
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        IBooster booster = strategyData.booster;
        SafeTransferLib.safeApprove(asset(), address(booster), assets);
        booster.deposit(strategyData.pid, assets, true);
    }

    /// @notice Withdraws specified amount of assets from Convex reward pool
    /// @param assets The amount of assets to withdraw
    function _withdraw(uint256 assets) internal override {
        strategyData.rewarder.withdrawAndUnwrap(assets, false);
    }

    /// @notice Gets the balance of assets inside Convex reward pool
    /// @return The current balance of assets
    function _getRealPositionBalance()
        internal
        view
        override
        returns (uint256)
    {
        return strategyData.rewarder.balanceOf(address(this));
    }

    /// @notice Adds underlying tokens to the vaults Curve 4Pool LP
    function _addLiquidityToCurve(uint256 minLPAmount) internal {
        address underlyingToken;
        uint256[4] memory amounts;

        bool liquidityAvailable;
        uint256 value;
        for (uint256 i; i < 4; ++i) {
            underlyingToken = strategyData.underlyingTokens[i];
            amounts[i] = CommonLib.getTokenBalance(underlyingToken);

            if (CommonLib.isETH(underlyingToken)) {
                value = amounts[i];
            }

            SwapperLib.approveTokenIfNeeded(
                underlyingToken,
                address(strategyData.curvePool),
                amounts[i]
            );

            if (amounts[i] > 0) {
                liquidityAvailable = true;
            }
        }

        if (liquidityAvailable) {
            strategyData.curvePool.add_liquidity{ value: value }(
                amounts,
                minLPAmount
            );
        }
    }

    /// @notice pre calculation logic for migration start
    /// @param newVault The new vault address
    function _migrationStart(
        address newVault
    ) internal override returns (bytes memory) {
        // claim convex rewards
        strategyData.rewarder.getReward(address(this), true);
        uint256 numRewardTokens = strategyData.rewardTokens.length;
        for (uint256 i; i < numRewardTokens; ++i) {
            SafeTransferLib.safeApprove(
                strategyData.rewardTokens[i],
                newVault,
                type(uint256).max
            );
        }
    }
}