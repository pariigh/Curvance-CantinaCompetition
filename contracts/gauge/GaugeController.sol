// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { GaugeErrors } from "contracts/gauge/GaugeErrors.sol";

import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IGaugePool } from "contracts/interfaces/IGaugePool.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IVeCVE } from "contracts/interfaces/IVeCVE.sol";

contract GaugeController is IGaugePool {

    /// structs
    struct Epoch {
        uint256 rewardPerSec;
        uint256 totalWeights;
        mapping(address => uint256) poolWeights; // token => weight
    }

    /// constants
    uint256 public constant EPOCH_WINDOW = 2 weeks;
    ICentralRegistry public immutable centralRegistry;
    address public immutable cve;
    IVeCVE public immutable veCVE;

    /// storage
    uint256 public startTime;
    mapping(uint256 => Epoch) internal epochInfo;

    constructor(ICentralRegistry centralRegistry_){
        centralRegistry = centralRegistry_;
        cve = centralRegistry.CVE();
        veCVE = IVeCVE(centralRegistry.veCVE());
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyMessagingHub() {
        require(
            msg.sender == centralRegistry.protocolMessagingHub(),
            "cveLocker: UNAUTHORIZED"
        );
        _;
    }

    /// @notice Start gauge system
    /// @dev Only owner
    function start() external onlyDaoPermissions {
        if (startTime != 0) {
            revert GaugeErrors.AlreadyStarted();
        }
        startTime = veCVE.nextEpochStartTime();
    }

    /// @notice Returns current epoch number
    function currentEpoch() public view returns (uint256) {
        assert(startTime != 0);
        return (block.timestamp - startTime) / EPOCH_WINDOW;
    }

    /// @notice Returns epoch number of given timestamp
    /// @param timestamp Timestamp in seconds
    function epochOfTimestamp(
        uint256 timestamp
    ) public view returns (uint256) {
        assert(startTime != 0);
        return (timestamp - startTime) / EPOCH_WINDOW;
    }

    /// @notice Returns start time of given epoch
    /// @param epoch Epoch number
    function epochStartTime(uint256 epoch) public view returns (uint256) {
        assert(startTime != 0);
        return startTime + epoch * EPOCH_WINDOW;
    }

    /// @notice Returns end time of given epoch
    /// @param epoch Epoch number
    function epochEndTime(uint256 epoch) public view returns (uint256) {
        assert(startTime != 0);
        return startTime + (epoch + 1) * EPOCH_WINDOW;
    }

    /// @notice Returns reward per second of given epoch
    /// @param epoch Epoch number
    function rewardPerSec(uint256 epoch) external view returns (uint256) {
        return epochInfo[epoch].rewardPerSec;
    }

    /// @notice Returns gauge weight of given epoch and token
    /// @param epoch Epoch number
    /// @param token Gauge token address
    function gaugeWeight(
        uint256 epoch,
        address token
    ) external view returns (uint256, uint256) {
        return (
            epochInfo[epoch].totalWeights,
            epochInfo[epoch].poolWeights[token]
        );
    }

    /// @notice Returns if given gauge token is enabled in given epoch
    /// @param epoch Epoch number
    /// @param token Gauge token address
    function isGaugeEnabled(
        uint256 epoch,
        address token
    ) public view returns (bool) {
        return epochInfo[epoch].poolWeights[token] > 0;
    }

    /// @notice Set rewardPerSec of next epoch
    /// @dev Only owner
    /// @param epoch Next epoch number
    /// @param newRewardPerSec Reward per second
    function setRewardPerSecOfNextEpoch(
        uint256 epoch,
        uint256 newRewardPerSec
    ) external override onlyMessagingHub {
        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 prevRewardPerSec = epochInfo[epoch].rewardPerSec;
        epochInfo[epoch].rewardPerSec = newRewardPerSec;

        if (prevRewardPerSec > newRewardPerSec) {
            SafeTransferLib.safeTransfer(cve,
                msg.sender,
                EPOCH_WINDOW * (prevRewardPerSec - newRewardPerSec)
            );
        } else {
            SafeTransferLib.safeTransferFrom(cve,
                msg.sender,
                address(this),
                EPOCH_WINDOW * (newRewardPerSec - prevRewardPerSec)
            );
        }
    }

    /// @notice Set emission rates of tokens of next epoch
    /// @dev Only the protocol messaging hub can call this
    /// @param epoch Next epoch number
    /// @param tokens Token address array
    /// @param poolWeights Gauge weights (or gauge weights)
    function setEmissionRates(
        uint256 epoch,
        address[] calldata tokens,
        uint256[] calldata poolWeights
    ) external override onlyMessagingHub {
        if (!(epoch == 0 && startTime == 0) && epoch != currentEpoch() + 1) {
            revert GaugeErrors.InvalidEpoch();
        }

        uint256 numTokens = tokens.length;

        if (numTokens != poolWeights.length) {
            revert GaugeErrors.InvalidLength();
        }

        Epoch storage info = epochInfo[epoch];
        for (uint256 i; i < numTokens; ) {
            info.totalWeights =
                info.totalWeights +
                poolWeights[i] -
                info.poolWeights[tokens[i]];
            info.poolWeights[tokens[i]] = poolWeights[i];

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Update reward variables for all pools
    /// @dev Be careful of gas spending!
    function massUpdatePools(address[] memory tokens) public {
        uint256 numTokens = tokens.length;
        for (uint256 i; i < numTokens; ) {
            unchecked {
                updatePool(tokens[i++]);
            }
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date
    /// @param token Pool token address
    function updatePool(address token) public virtual {}
}
