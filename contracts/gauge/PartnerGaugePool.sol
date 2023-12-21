// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";
import { GaugePool } from "contracts/gauge/GaugePool.sol";
import { GaugeErrors } from "contracts/gauge/GaugeController.sol";

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { ReentrancyGuard } from "contracts/libraries/ReentrancyGuard.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";

contract PartnerGaugePool is ReentrancyGuard {
    /// TYPES ///

    struct PoolInfo {
        uint256 lastRewardTimestamp;
        // Accumulated Rewards per share, times 1e12. See below.
        uint256 accRewardPerShare;
        uint256 totalAmount;
    }

    struct UserInfo {
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    enum UserAction {
        DEPOSIT,
        WITHDRAW,
        CLAIM
    }

    /// CONSTANTS ///

    uint256 public constant EPOCH_WINDOW = 2 weeks; // VeCVE epoch length
    uint256 public constant PRECISION = 1e36; // Scalar for math
    GaugePool public immutable gaugeController; // Gauge Controller linked
    address public immutable rewardToken; // Token partner gauge rewards in
    ICentralRegistry public immutable centralRegistry; // Curvance DAO hub

    /// STORAGE ///

    uint256 public activationTime; // Partner gauge emission start time

    // epoch => rewardPerSec
    mapping(uint256 => uint256) public epochRewardPerSec;
    // token => pool info
    mapping(address => PoolInfo) public poolInfo;
    // token => user => info
    mapping(address => mapping(address => UserInfo)) public userInfo;
    uint256 public firstDeposit;
    uint256 public unallocatedRewards;

    /// CONSTRUCTOR ///

    constructor(
        address gaugeController_,
        address rewardToken_,
        ICentralRegistry centralRegistry_
    ) {
        if (
            !ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            )
        ) {
            revert GaugeErrors.InvalidAddress();
        }

        centralRegistry = centralRegistry_;

        if (!centralRegistry_.isGaugeController(gaugeController_)) {
            revert GaugeErrors.InvalidAddress();
        }

        gaugeController = GaugePool(gaugeController_);
        rewardToken = rewardToken_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Start the Partner Gauge at the start of the Gauge Controller's next epoch
    function activate() external {
        _checkIsGaugeController();

        activationTime = gaugeController.epochStartTime(
            gaugeController.currentEpoch() + 1
        );
    }

    function setRewardPerSec(
        uint256 epoch,
        uint256 newRewardPerSec
    ) external {
        if (!centralRegistry.hasDaoPermissions(msg.sender)) {
            revert GaugeErrors.Unauthorized();
        }

        if (!(epoch == 0 && startTime() == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = epochRewardPerSec[epoch];
        epochRewardPerSec[epoch] = newRewardPerSec;

        if (prevRewardPerSec > newRewardPerSec) {
            SafeTransferLib.safeTransfer(
                rewardToken,
                msg.sender,
                EPOCH_WINDOW * (prevRewardPerSec - newRewardPerSec)
            );
        } else {
            SafeTransferLib.safeTransferFrom(
                rewardToken,
                msg.sender,
                address(this),
                EPOCH_WINDOW * (newRewardPerSec - prevRewardPerSec)
            );
        }
    }

    /// @notice Returns pending rewards of user
    /// @param token Pool token address
    /// @param user User address
    function pendingRewards(
        address token,
        address user
    ) external view returns (uint256) {
        if (
            !gaugeController.isGaugeEnabled(
                gaugeController.currentEpoch(),
                token
            )
        ) {
            revert GaugeErrors.InvalidToken();
        }

        uint256 accRewardPerShare = poolInfo[token].accRewardPerShare;
        uint256 lastRewardTimestamp = poolInfo[token].lastRewardTimestamp;
        uint256 totalDeposited = gaugeController.totalSupply(token);

        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = activationTime;
        }

        if (block.timestamp > lastRewardTimestamp && totalDeposited != 0) {
            uint256 lastEpoch = gaugeController.epochOfTimestamp(
                lastRewardTimestamp
            );
            uint256 curEpoch = gaugeController.currentEpoch();
            uint256 reward;
            while (lastEpoch < curEpoch) {
                uint256 endTimestamp = gaugeController.epochEndTime(lastEpoch);

                (uint256 totalWeights, uint256 poolWeights) = gaugeController
                    .gaugeWeight(lastEpoch, token);
                // update rewards from lastRewardTimestamp to endTimestamp
                reward =
                    ((endTimestamp - lastRewardTimestamp) *
                        epochRewardPerSec[lastEpoch] *
                        poolWeights) /
                    totalWeights;
                accRewardPerShare =
                    accRewardPerShare +
                    (reward * (PRECISION)) /
                    totalDeposited;

                ++lastEpoch;
                lastRewardTimestamp = endTimestamp;
            }

            (
                uint256 totalWeightsOfCurrentEpoch,
                uint256 poolWeightsOfCurrentEpoch
            ) = gaugeController.gaugeWeight(lastEpoch, token);
            // update rewards from lastRewardTimestamp to current timestamp
            reward =
                ((block.timestamp - lastRewardTimestamp) *
                    epochRewardPerSec[lastEpoch] *
                    poolWeightsOfCurrentEpoch) /
                totalWeightsOfCurrentEpoch;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;
        }

        UserInfo memory info = userInfo[token][user];
        return
            info.rewardPending +
            (gaugeController.balanceOf(token, user) * accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    function deposit(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        _checkIsGaugeController();
        
        _updatePool(token, UserAction.DEPOSIT, amount);

        _calcPending(user, token, UserAction.DEPOSIT, amount);

        if (firstDeposit == 0) {
            // if first deposit, the new rewards from gauge start to this point will be unallocated rewards
            firstDeposit = block.timestamp;
            _updatePool(token, UserAction.DEPOSIT, 0);
            SafeTransferLib.safeTransfer(
                rewardToken,
                centralRegistry.daoAddress(),
                (poolInfo[token].accRewardPerShare *
                    gaugeController.totalSupply(token)) / PRECISION
            );
        }

        _calcDebt(user, token);
    }

    function withdraw(
        address token,
        address user,
        uint256 amount
    ) external nonReentrant {
        _checkIsGaugeController();
        
        _updatePool(token, UserAction.WITHDRAW, amount);

        _calcPending(user, token, UserAction.WITHDRAW, amount);

        _calcDebt(user, token);
    }

    function claim(address token) external nonReentrant {
        _updatePool(token, UserAction.CLAIM, 0);

        _calcPending(msg.sender, token, UserAction.CLAIM, 0);

        uint256 rewards = userInfo[token][msg.sender].rewardPending;
        if (rewards == 0) {
            revert GaugeErrors.NoReward();
        }
        SafeTransferLib.safeTransfer(rewardToken, msg.sender, rewards);

        userInfo[token][msg.sender].rewardPending = 0;

        _calcDebt(msg.sender, token);
    }

    /// PUBLIC FUNCTIONS ///

    function startTime() public view returns (uint256) {
        return gaugeController.startTime();
    }

    function currentEpoch() public view returns (uint256) {
        return gaugeController.currentEpoch();
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Calculate user's pending rewards
    function _calcPending(
        address user,
        address token,
        UserAction action,
        uint256 amount
    ) internal {
        uint256 userAmount = gaugeController.balanceOf(token, user);
        if (action == UserAction.DEPOSIT) {
            userAmount -= amount;
        } else if (action == UserAction.WITHDRAW) {
            userAmount += amount;
        }

        UserInfo storage info = userInfo[token][user];
        info.rewardPending +=
            (userAmount * poolInfo[token].accRewardPerShare) /
            (PRECISION) -
            info.rewardDebt;
    }

    /// @notice Calculate user's debt amount for reward calculation
    function _calcDebt(address user, address token) internal {
        UserInfo storage info = userInfo[token][user];
        info.rewardDebt =
            (gaugeController.balanceOf(token, user) *
                poolInfo[token].accRewardPerShare) /
            (PRECISION);
    }

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function _updatePool(
        address token,
        UserAction action,
        uint256 amount
    ) internal {
        PoolInfo storage _pool = poolInfo[token];
        uint256 lastRewardTimestamp = _pool.lastRewardTimestamp;

        if (lastRewardTimestamp == 0) {
            _pool.lastRewardTimestamp = activationTime;
            lastRewardTimestamp = activationTime;
        }

        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 totalDeposited = gaugeController.totalSupply(token);
        if (action == UserAction.DEPOSIT) {
            totalDeposited -= amount;
        } else if (action == UserAction.WITHDRAW) {
            totalDeposited += amount;
        }

        if (totalDeposited == 0) {
            _pool.lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 accRewardPerShare = _pool.accRewardPerShare;
        uint256 lastEpoch = gaugeController.epochOfTimestamp(
            lastRewardTimestamp
        );
        uint256 curEpoch = gaugeController.currentEpoch();
        uint256 reward;
        while (lastEpoch < curEpoch) {
            uint256 endTimestamp = gaugeController.epochEndTime(lastEpoch);

            (uint256 totalWeights, uint256 poolWeights) = gaugeController
                .gaugeWeight(lastEpoch, token);

            // update rewards from lastRewardTimestamp to endTimestamp
            reward =
                ((endTimestamp - lastRewardTimestamp) *
                    epochRewardPerSec[lastEpoch] *
                    poolWeights) /
                totalWeights;
            accRewardPerShare =
                accRewardPerShare +
                (reward * (PRECISION)) /
                totalDeposited;

            ++lastEpoch;
            lastRewardTimestamp = endTimestamp;
        }

        (
            uint256 totalWeightsOfCurrentEpoch,
            uint256 poolWeightsOfCurrentEpoch
        ) = gaugeController.gaugeWeight(lastEpoch, token);
        // update rewards from lastRewardTimestamp to current timestamp
        reward =
            ((block.timestamp - lastRewardTimestamp) *
                epochRewardPerSec[lastEpoch] *
                poolWeightsOfCurrentEpoch) /
            totalWeightsOfCurrentEpoch;
        accRewardPerShare =
            accRewardPerShare +
            (reward * (PRECISION)) /
            totalDeposited;

        // update pool storage
        _pool.lastRewardTimestamp = block.timestamp;
        _pool.accRewardPerShare = accRewardPerShare;
    }

    /// @dev Checks whether the caller has sufficient permissioning
    function _checkIsGaugeController() internal view {
        if (msg.sender != address(gaugeController)) {
            revert GaugeErrors.Unauthorized();
        }
    }
}