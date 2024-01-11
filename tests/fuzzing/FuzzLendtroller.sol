pragma solidity 0.8.17;
import { StatefulBaseMarket } from "tests/fuzzing/StatefulBaseMarket.sol";
import { MockCToken } from "contracts/mocks/MockCToken.sol";
import { MockDataFeed } from "contracts/mocks/MockDataFeed.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { SafeTransferLib } from "contracts/libraries/SafeTransferLib.sol";
import { MockToken } from "contracts/mocks/MockToken.sol";
import { IMToken } from "contracts/market/lendtroller/LiquidityManager.sol";
import { WAD } from "contracts/libraries/Constants.sol";

contract FuzzLendtroller is StatefulBaseMarket {
    MockDataFeed public mockUsdcFeed;
    MockDataFeed public mockDaiFeed;
    bool feedsSetup;
    uint256 lastRoundUpdate;
    mapping(address => bool) setCollateralValues;
    mapping(address => bool) collateralCapsUpdated;
    mapping(address => bool) postedCollateral;
    mapping(address => uint256) postedCollateralAt;

    constructor() {
        SafeTransferLib.safeApprove(
            _USDC_ADDRESS,
            address(dUSDC),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _DAI_ADDRESS,
            address(dDAI),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _USDC_ADDRESS,
            address(cUSDC),
            type(uint256).max
        );
        SafeTransferLib.safeApprove(
            _DAI_ADDRESS,
            address(cDAI),
            type(uint256).max
        );
    }

    // Test Property: calling listToken for a token should succeed
    // Test Precondition: mtoken must not already be listed
    // Test Precondition: mtoken must be one of: cDAI, cUSDC
    function list_token_should_succeed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the lendtroller
        require(!lendtroller.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try lendtroller.listToken(mtoken) {
            assertWithMsg(
                lendtroller.isListed(mtoken),
                "LENDTROLLER - lendtroller.listToken() should succeed"
            );
        } catch {
            assertWithMsg(false, "LENDTROLLER - failed to list token");
        }
    }

    // Test Property: calling listToken() for a token that already exists should fail
    // Test Precondition: mtoken must already be listed
    // Test Precondition: mtoken must be one of: cDAI, cUSDC
    function list_token_should_fail_if_already_listed(address mtoken) public {
        uint256 amount = 42069;
        // require the token is not already listed into the lendtroller
        require(lendtroller.isListed(mtoken));

        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        address underlyingAddress = MockCToken(mtoken).underlying();
        IERC20 underlying = IERC20(underlyingAddress);

        try lendtroller.listToken(mtoken) {
            assertWithMsg(
                false,
                "LENDTROLLER - listToken for duplicate token should not be possible"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_tokenAlreadyListedSelectorHash,
                "LENDTROLLER - listToken() expected TokenAlreadyListed selector hash on failure"
            );
        }
    }

    // function c_token_depositAsCollateral(
    //     address mtoken,
    //     uint256 amount
    // ) public {
    //     amount = clampBetween(amount, 1, type(uint32).max);
    //     // require gauge pool has been started at a previous timestamp
    //     require(gaugePool.startTime() < block.timestamp);
    //     require(mtoken == address(cDAI) || mtoken == address(cUSDC));
    //     if (!lendtroller.isListed(mtoken)) {
    //         list_token_should_succeed(mtoken);
    //     }

    //     address underlyingAddress = MockCToken(mtoken).underlying();
    //     // mint ME enough tokens to cover deposit
    //     try MockToken(underlyingAddress).mint(amount) {} catch {
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - mint underlying amount should succeed before deposit"
    //         );
    //     }
    //     // approve sufficient underlying tokens prior to calling deposit
    //     try MockToken(underlyingAddress).approve(mtoken, amount) {} catch {
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - approve underlying amount should succeed before deposit"
    //         );
    //     }
    //     uint256 preCTokenBalanceThis = MockCToken(mtoken).balanceOf(
    //         address(this)
    //     );

    //     // This step should mint associated shares for the user
    //     try MockCToken(mtoken).depositAsCollateral(amount, address(this)) {
    //         uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
    //             address(this)
    //         );

    //         assertLt(
    //             preCTokenBalanceThis,
    //             postCTokenBalanceThis,
    //             "LENDTROLLER - pre and post ctoken balance should increase"
    //         );
    //     } catch (bytes memory revertData) {
    //         emit LogAddress("msg.sender", msg.sender);
    //         uint256 errorSelector = extractErrorSelector(revertData);

    //         emit LogUint256("error selector: ", errorSelector);
    //         assertWithMsg(
    //             false,
    //             "LENDTROLLER - expected mtoken.deposit() to be successful"
    //         );
    //     }
    // }

    // Test Property: After depositing, the ctoken balance should increase
    // Test Precondition: amount bound between [1, uint16.max], inclusively
    // Test Precondition: GaugePool must have been started before block.timestamp
    // Test Precondition: mtoken must be one of: cDAI, cUSDC
    // Test Precondition: mtoken must be listed in Lendtroller
    // Test Precondition: minting must not be paused
    function c_token_deposit(address mtoken, uint256 amount) public {
        amount = clampBetween(amount, 1, type(uint16).max);
        require(gaugePool.startTime() < block.timestamp);
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(lendtroller.mintPaused(mtoken) != 2);

        address underlyingAddress = MockCToken(mtoken).underlying();
        // mint ME enough tokens to cover deposit
        try MockToken(underlyingAddress).mint(amount) {} catch {
            uint256 currentSupply = MockToken(underlyingAddress).totalSupply();

            // if the total supply overflowed, then this is actually expected to revert
            if (currentSupply + amount < currentSupply) {
                return;
            }

            assertWithMsg(
                false,
                "LENDTROLLER - mint underlying amount should succeed before deposit"
            );
        }
        // approve sufficient underlying tokens prior to calling deposit
        try MockToken(underlyingAddress).approve(mtoken, amount) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - approve underlying amount should succeed before deposit"
            );
        }
        uint256 preCTokenBalanceThis = MockCToken(mtoken).balanceOf(
            address(this)
        );

        // This step should mint associated shares for the user
        try MockCToken(mtoken).deposit(amount, address(this)) {
            uint256 postCTokenBalanceThis = MockCToken(mtoken).balanceOf(
                address(this)
            );

            assertLt(
                preCTokenBalanceThis,
                postCTokenBalanceThis,
                "LENDTROLLER - pre and post ctoken balance should increase"
            );
        } catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            emit LogUint256("error selector: ", errorSelector);
            assertWithMsg(
                false,
                "LENDTROLLER - expected mtoken.deposit() to be successful"
            );
        }
    }

    function setUpFeeds() public {
        require(centralRegistry.hasElevatedPermissions(address(this)));
        require(gaugePool.startTime() < block.timestamp);
        // use mock pricing for testing
        // StatefulBaseMarket - chainlinkAdaptor - usdc, dai
        mockUsdcFeed = new MockDataFeed(address(chainlinkUsdcUsd));
        chainlinkAdaptor.addAsset(address(cUSDC), address(mockUsdcFeed), true);
        dualChainlinkAdaptor.addAsset(
            address(cUSDC),
            address(mockUsdcFeed),
            true
        );
        mockDaiFeed = new MockDataFeed(address(chainlinkDaiUsd));
        chainlinkAdaptor.addAsset(address(cDAI), address(mockDaiFeed), true);
        dualChainlinkAdaptor.addAsset(
            address(cDAI),
            address(mockDaiFeed),
            true
        );

        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        chainlinkUsdcUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        chainlinkDaiUsd.updateRoundData(
            0,
            1e8,
            block.timestamp,
            block.timestamp
        );
        priceRouter.addMTokenSupport(address(cDAI));
        priceRouter.addMTokenSupport(address(cUSDC));

        feedsSetup = true;
        lastRoundUpdate = block.timestamp;
    }

    // Test Property: collateralCaps[mtoken] after calling setCTokenCollateralCaps is updated
    // Test Precondition: price feed must be recent
    // Test Precondition: price feed must be setup
    // Test Precondition: address(this) must have dao permissions
    // Test Precondition: cap is bound between [1, uint256.max], inclusive
    // Test Precondition: mtoken must be listed in the Lendtroller
    // Test Precondition: get_safe_update_collateral_bounds must be in correct bounds
    function updateCollateralToken_should_succeed(
        address mtoken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor,
        uint256 cap
    ) public {
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        cap = clampBetween(cap, 1, type(uint256).max);
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));

        TokenCollateralBounds
            memory bounds = get_safe_update_collateral_bounds(
                collRatio,
                collReqSoft,
                collReqHard,
                liqIncSoft,
                liqIncHard,
                liqFee,
                baseCFactor
            );
        check_price_feed();
        try
            lendtroller.updateCollateralToken(
                IMToken(address(mtoken)),
                bounds.collRatio,
                bounds.collReqSoft,
                bounds.collReqHard,
                bounds.liqIncSoft,
                bounds.liqIncHard,
                bounds.liqFee,
                bounds.baseCFactor
            )
        {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - updateCollateralToken should succeed"
            );
        }
        setCollateralValues[mtoken] = true;
    }

    function setCToken_should_succeed(address mtoken, uint256 cap) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(setCollateralValues[mtoken]);
        check_price_feed();

        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setCTokenCollateralCaps(address[],uint256[])",
                tokens,
                caps
            )
        );

        if (success) {
            assertGt(
                lendtroller.collateralCaps(mtoken),
                0,
                "LENDTROLLER - collateral caps for token should be >0"
            );
        } else {
            assertWithMsg(
                false,
                "LENDTROLLER - expected setCTokenCollateralCaps to succeed"
            );
        }

        collateralCapsUpdated[mtoken] = true;
    }

    // Test Property: updateCollateralToken should revert if the price feed is out of date
    // Test Precondition: price feed is out of date
    // Test Precondition: cap is bound between [1, uint256.max], inclusive
    // Test Precondition: mtoken must be listed in Lendtroller
    // Test Precondition: mtoken must be one of: cDAI, cUSDC
    function updateCollateralToken_should_revert_if_price_feed_out_of_date(
        address mtoken,
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor,
        uint256 cap
    ) public {
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        require(block.timestamp - lastRoundUpdate > 24 hours);
        if (mtoken == address(cDAI)) {
            require(
                block.timestamp - chainlinkDaiUsd.latestTimestamp() > 24 hours
            );
        } else if (mtoken == address(cUSDC)) {
            require(
                block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours
            );
        } else {
            return;
        }
        require(feedsSetup);
        require(centralRegistry.hasDaoPermissions(address(this)));
        cap = clampBetween(cap, 1, type(uint256).max);
        if (!lendtroller.isListed(mtoken)) {
            list_token_should_succeed(mtoken);
        }
        address[] memory tokens = new address[](1);
        tokens[0] = mtoken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;

        TokenCollateralBounds
            memory bounds = get_safe_update_collateral_bounds(
                collRatio,
                collReqSoft,
                collReqHard,
                liqIncSoft,
                liqIncHard,
                liqFee,
                baseCFactor
            );
        try
            lendtroller.updateCollateralToken(
                IMToken(address(mtoken)),
                bounds.collRatio,
                bounds.collReqSoft,
                bounds.collReqHard,
                bounds.liqIncSoft,
                bounds.liqIncHard,
                bounds.liqFee,
                bounds.baseCFactor
            )
        {
            assertWithMsg(
                false,
                "LENDTROLLER - updateCollateralToken should not have succeeded with out of date price feeds"
            );
        } catch {}
    }

    // Test Property: Ensure account collateral has increased by # of tokens
    // Test Property: Ensure user has a valid position after posting
    // Test Property: Ensure collateralPosted (for mtoken) has increased by # of tokens
    // Test Precondition: price feed is up to date
    // Test Precondition: address(this) must have a balance of mtoken
    // Test Precondition: `tokens` to be posted is bound between [1, mtoken balance], inclusive
    // Test Precondition: msg.sender for postCollateral = address(this)
    function post_collateral_should_succeed(
        address mtoken,
        uint256 tokens
    ) public {
        if (!collateralCapsUpdated[mtoken]) {
            setCToken_should_succeed(mtoken, tokens);
        }
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(mtoken, tokens * IMToken(mtoken).decimals());
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );
        uint256 collateralCaps = lendtroller.collateralCaps(mtoken);

        uint256 oldCollateralForToken = lendtroller.collateralPosted(mtoken);
        if (
            mtokenBalance - oldCollateralForUser >
            collateralCaps - oldCollateralForToken
        ) {
            // collateralPosted[mToken] + tokens <= collateralCaps[mToken])
            // tokens <= collateralCaps[mtoken] - collateralPosted[mtoken]
            tokens = clampBetween(
                tokens,
                1,
                collateralCaps - oldCollateralForToken
            );
        } else {
            // collateralPosted + tokens <= mtoken.balanceOf(address(this))
            // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
            tokens = clampBetween(
                tokens,
                1,
                mtokenBalance - oldCollateralForUser
            );
        }

        {
            (bool success, bytes memory revertData) = address(lendtroller)
                .call(
                    abi.encodeWithSignature(
                        "postCollateral(address,address,uint256)",
                        address(this),
                        mtoken,
                        tokens
                    )
                );
            if (!success) {
                uint256 errorSelector = extractErrorSelector(revertData);
                emit LogUint256("error selector: ", errorSelector);

                assertWithMsg(
                    false,
                    "LENDTROLLER - expected postCollateral to pass with preconditions"
                );
            }
            // ensure account collateral has increased by # of tokens
            uint256 newCollateralForUser = lendtroller.collateralPostedFor(
                mtoken,
                address(this)
            );

            assertEq(
                newCollateralForUser,
                oldCollateralForUser + tokens,
                "LENDTROLLER - new collateral must collateral+tokens"
            );
            // ensure that a user has a position after posting
            assertWithMsg(
                lendtroller.hasPosition(mtoken, address(this)),
                "LENDTROLLER - addr(this) must have position after posting"
            );
            // ensure collateralPosted increases by tokens
            uint256 newCollateralForToken = lendtroller.collateralPosted(
                mtoken
            );
            assertEq(
                newCollateralForToken,
                oldCollateralForToken + tokens,
                "LENDTROLLER - global collateral posted should increase"
            );
        }
        postedCollateral[mtoken] = true;
        postedCollateralAt[mtoken] = block.timestamp;
    }

    // Test Property: postCollateral with token bounded too large should fail
    // Test Precondition: collateral caps for the token are >0
    // Test Precondition: price feed must be out of date
    // Test Precondition: user must have mtoken balance
    function post_collateral_should_fail_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(collateralCapsUpdated[mtoken]);
        check_price_feed();

        if (IMToken(mtoken).balanceOf(address(this)) == 0) {
            c_token_deposit(mtoken, tokens * IMToken(mtoken).decimals());
        }
        uint256 mtokenBalance = IMToken(mtoken).balanceOf(address(this));

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );

        // collateralPosted + tokens <= mtoken.balanceOf(address(this))
        // tokens <= mtoken.balanceOf(address(this)) - collateralPosted
        tokens = clampBetween(
            tokens,
            mtokenBalance - oldCollateralForUser + 1,
            type(uint64).max
        );

        uint256 oldCollateralForToken = lendtroller.collateralPosted(mtoken);

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "postCollateral(address,address,uint256)",
                address(this),
                mtoken,
                tokens
            )
        );

        assertWithMsg(
            !success,
            "LENDTROLLER - postCollateral() with too many tokens should fail"
        );
    }

    // Test Property: Global posted collateral for the token should decrease by removed amount
    // Test Property: User posted collateral for token should decrease by removed amount
    // Test Property: If there is a shortfall, the removeCollateral call should fail
    // Test Property: If there is no shortfall, the removeCollateral call should succeed
    // Test Preconditions: price feed must be recent
    // Test Preconditions: mtoken is one of: cDAI, cUSDC
    // Test Preconditions: mtoken must be listed in the Lendtroller
    // Test Preconditions: current timestamp must exceed the MIN_HOLD_PERIOD from postCollateral timestamp
    // Test Preconditions: token is clamped between [1, collateralForUser]
    // Test Preconditions: redeemPaused flag must not be set
    function remove_collateral_should_succeed(
        address mtoken,
        uint256 tokens,
        bool closePositionIfPossible
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(postedCollateral[mtoken]);
        require(lendtroller.isListed(mtoken));
        check_price_feed();

        require(
            block.timestamp >
                postedCollateralAt[mtoken] + lendtroller.MIN_HOLD_PERIOD()
        );
        require(lendtroller.hasPosition(mtoken, address(this)));
        require(lendtroller.redeemPaused() != 2);

        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );
        tokens = clampBetween(tokens, 1, oldCollateralForUser);

        uint256 oldCollateralPostedForToken = lendtroller.collateralPosted(
            mtoken
        );
        (, uint256 shortfall) = lendtroller.hypotheticalLiquidityOf(
            address(this),
            mtoken,
            tokens,
            0
        );

        if (shortfall > 0) {
            (bool success, bytes memory revertData) = address(lendtroller)
                .call(
                    abi.encodeWithSignature(
                        "removeCollateral(address,uint256,bool)",
                        mtoken,
                        tokens,
                        closePositionIfPossible
                    )
                );
            // If the call failed, ensure that the revert message is insufficient collateral
            if (!success) {
                uint256 errorSelector = extractErrorSelector(revertData);

                assertWithMsg(
                    errorSelector ==
                        lendtroller_insufficientCollateralSelectorHash,
                    "LENDTROLLER - reduceCollateralIfNecessary expected to revert with insufficientCollateral"
                );
            }
        } else {
            (bool success, bytes memory rd) = address(lendtroller).call(
                abi.encodeWithSignature(
                    "removeCollateral(address,uint256,bool)",
                    mtoken,
                    tokens,
                    closePositionIfPossible
                )
            );
            // Collateral posted for the mtoken should decrease
            uint256 newCollateralPostedForToken = lendtroller.collateralPosted(
                mtoken
            );
            assertEq(
                newCollateralPostedForToken,
                oldCollateralPostedForToken - tokens,
                "LENDTROLLER - global collateral posted should decrease"
            );

            // Collateral posted for the user should decrease
            uint256 newCollateralForUser = lendtroller.collateralPostedFor(
                mtoken,
                address(this)
            );
            assertEq(
                newCollateralForUser,
                oldCollateralForUser - tokens,
                "LENDTROLLER - user collateral posted should decrease"
            );
            if (newCollateralForUser == 0 && closePositionIfPossible) {
                assertWithMsg(
                    !lendtroller.hasPosition(mtoken, address(this)),
                    "LENDTROLLER - closePositionIfPossible flag set should remove a user's position"
                );
            }
        }
    }

    // Test Property: removeCollateral should REVERT when no position exists
    // Test Precondition: mtoken is either of: cDAI or cUSDC
    // Test Precondition: token must be listed in Lendtroller
    // Test Precondition: price feed must be up to date
    // Test Precondition: user must NOT have an existing position
    function removeCollateral_should_fail_with_non_existent_position(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.isListed(mtoken));
        check_price_feed();
        require(!lendtroller.hasPosition(mtoken, address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "removeCollateral(address,uint256,bool)",
                mtoken,
                tokens,
                false
            )
        );

        if (success) {
            assertWithMsg(
                false,
                "LENDTROLLER - removeCollateral should fail with non existent position"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_invariantErrorSelectorHash,
                "LENDTROLLER - expected removeCollateral to revert with InvariantError"
            );
        }
    }

    // Test Property: removeCollateral should REVERT when trying to remove too much
    // Test Precondition: mtoken is either of: cDAI or cUSDC
    // Test Precondition: token must be listed in Lendtroller
    // Test Precondition: price feed must be up to date
    // Test Precondition: user must have an existing position
    // Test Precondition: tokens to remove is bound between [existingCollateral+1, uint32.max]
    function removeCollateral_should_fail_with_removing_too_many_tokens(
        address mtoken,
        uint256 tokens
    ) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.isListed(mtoken));
        check_price_feed();
        require(lendtroller.hasPosition(mtoken, address(this)));
        uint256 oldCollateralForUser = lendtroller.collateralPostedFor(
            mtoken,
            address(this)
        );

        tokens = clampBetween(
            tokens,
            oldCollateralForUser + 1,
            type(uint32).max
        );

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "removeCollateral(address,uint256,bool)",
                mtoken,
                tokens,
                false
            )
        );

        if (success) {
            assertWithMsg(
                false,
                "LENDTROLLER - removeCollateral should fail insufficient collateral"
            );
        } else {
            // expectation is that this should fail
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector ==
                    lendtroller_insufficientCollateralSelectorHash,
                "LENDTROLLER - expected removeCollateral to revert with InsufficientCollateral when attempting to remove too much"
            );
        }
    }

    // Test Property: reduceCollateralIfNecessary should revert with unauthorized if called directly
    // Test Precondition: msg.sender != mtoken
    function reduceCollateralIfNecessary_should_fail_with_wrong_caller(
        address mtoken,
        uint256 amount
    ) public {
        require(msg.sender != mtoken);
        try
            lendtroller.reduceCollateralIfNecessary(
                address(this),
                mtoken,
                IMToken(mtoken).balanceOf(address(this)),
                amount
            )
        {} catch (bytes memory revertData) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - reduceCollateralIfNecessary expected to revert"
            );
        }
    }

    function closePosition_should_succeed(address mtoken) public {
        require(mtoken == address(cDAI) || mtoken == address(cUSDC));
        require(lendtroller.hasPosition(mtoken, address(this)));
        uint256 collateralPostedForUser = lendtroller.collateralPostedFor(
            address(mtoken),
            address(this)
        );
        IMToken[] memory preAssetsOf = lendtroller.assetsOf(address(this));

        (bool success, bytes memory rd) = address(lendtroller).call(
            abi.encodeWithSignature("closePosition(address)", mtoken)
        );
        if (!success) {} else {
            assertWithMsg(
                !lendtroller.hasPosition(mtoken, address(this)),
                "LENDTROLLER - closePosition should remove position in mtoken if successful"
            );
            assertWithMsg(
                lendtroller.collateralPostedFor(mtoken, address(this)) == 0,
                "LENDTROLLER - closePosition should reduce collateralPosted for user to 0"
            );
            IMToken[] memory postAssetsOf = lendtroller.assetsOf(
                address(this)
            );
            assertWithMsg(
                preAssetsOf.length - 1 == postAssetsOf.length,
                "LENDTROLLER - closePosition expected to remove asset from assetOf"
            );
        }
    }

    // Test Property: setMintPaused with correct preconditions should not revert
    // Test Property: setMintPaused should set mintPaused(mtoken) = 2 when state = true
    // Test Property: setMintPaused should set mintPaused(mtoken) = 1 when state = false
    // Test Precondition: address(this) is authorized
    // Test Preconditoin: mtoken is listed
    function setMintPaused_should_succeed_when_authorized_and_listed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(lendtroller.isListed(mtoken));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setMintPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isMintPaused = lendtroller.mintPaused(mtoken);
            if (state) {
                assertWithMsg(
                    isMintPaused == 2,
                    "LENDTROLLER - setMintPaused() true succeed set isMintPaused = 2"
                );
            } else {
                assertWithMsg(
                    isMintPaused == 1,
                    "LENDTROLLER - setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setMintPaused() expected to be successful with correct preconditions"
            );
        }
    }

    function canMint_should_not_revert_when_mint_not_paused_and_is_listed(
        address mToken
    ) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused != 2);
        require(isListed);

        try lendtroller.canMint(mToken) {} catch {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have not reverted"
            );
        }
    }

    function canMint_should_revert_when_token_is_not_listed(
        address mToken
    ) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused != 2);
        require(!isListed);

        try lendtroller.canMint(mToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when token is not listed but did not"
            );
        } catch {}
    }

    function canMint_should_revert_when_mint_is_paused(address mToken) public {
        uint256 mintPaused = lendtroller.mintPaused(mToken);
        bool isListed = lendtroller.isListed(mToken);

        require(mintPaused == 2);
        require(isListed);

        try lendtroller.canMint(mToken) {
            assertWithMsg(
                false,
                "LENDTROLLER - canMint() should have reverted when mint is paused but did not"
            );
        } catch {}
    }

    // Test Property: setRedeemPaused(true) should set redeemPaused = 2
    // Test Property: setRedeemPause(false) should set redeemPaused = 1
    // Test Preconditions: address(this) has dao permissions
    function setRedeemPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setRedeemPaused(bool)", state)
        );
        if (success) {
            uint256 redeemPaused = lendtroller.redeemPaused();
            if (state == true) {
                assertEq(
                    redeemPaused,
                    2,
                    "LENDTROLLER - setRedeemPaused() true expected to set redeemPaused = 2 "
                );
            } else {
                assertEq(
                    redeemPaused,
                    1,
                    "LENDTROLLER - setRedeemPaused false expected to set redeemPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                errorSelector == lendtroller_unauthorizedSelectorHash,
                "LENDTROLLER - setRedeemPaused() expected to be successful with correct preconditions"
            );
        }
    }

    function canRedeem_should_revert_when_redeem_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() == 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canRedeem(mToken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert when redeem is paused"
            );
        } catch {}
    }

    function canRedeem_should_revert_token_not_listed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.redeemPaused() != 2);
        require(!lendtroller.isListed(mToken));
        try lendtroller.canRedeem(mToken, account, amount) {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeem expected to revert token is not listed"
            );
        } catch {}
    }

    function canRedeemWithCollateralRemoval_should_fail(
        address account,
        address mtoken,
        uint256 balance,
        uint256 amount,
        bool forceRedeemCollateral
    ) public {
        require(msg.sender != mtoken);
        try
            lendtroller.canRedeemWithCollateralRemoval(
                account,
                mtoken,
                balance,
                amount,
                forceRedeemCollateral
            )
        {
            assertWithMsg(
                false,
                "LENDTROLLER - canRedeemWithCollateralRemoval should only be callable by mtoken"
            );
        } catch {}
    }

    function setBorrowPaused_should_succeed(
        address mtoken,
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));
        require(lendtroller.isListed(mtoken));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature(
                "setBorrowPaused(address,bool)",
                mtoken,
                state
            )
        );
        if (success) {
            uint256 isBorrowPaused = lendtroller.borrowPaused(mtoken);
            if (state) {
                assertWithMsg(
                    isBorrowPaused == 2,
                    "LENDTROLLER - setMintPaused() true succeed set isBorrowPaused = 2"
                );
            } else {
                assertWithMsg(
                    isBorrowPaused == 1,
                    "LENDTROLLER - setMintPaused() false should set mintPaused[mtoken] to 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setMintPaused() expected to be successful with correct preconditions"
            );
        }
    }

    function canBorrow_should_succeed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch {}
    }

    function canBorrow_should_fail_when_borrow_is_paused(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) == 2);
        require(lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_pausedSelectorHash,
                "LENDTROLLER - canBorrow() expected PAUSED selector hash on failure"
            );
        }
    }

    function canBorrow_should_fail_when_token_is_unlisted(
        address mToken,
        address account,
        uint256 amount
    ) public {
        require(lendtroller.borrowPaused(mToken) != 2);
        require(!lendtroller.isListed(mToken));
        try lendtroller.canBorrow(mToken, address(this), amount) {} catch (
            bytes memory revertData
        ) {
            uint256 errorSelector = extractErrorSelector(revertData);

            assertWithMsg(
                errorSelector == lendtroller_tokenNotListedSelectorHash,
                "LENDTROLLER - canBorrow() expected TOKEN NOT LISTED selector hash on failure"
            );
        }
    }

    function canBorrowWithNotify_should_succeed(
        address mToken,
        address account,
        uint256 amount
    ) public {
        try
            lendtroller.canBorrowWithNotify(mToken, account, amount)
        {} catch {}
    }

    function notifyBorrow_should_succeed(
        address mToken,
        address account
    ) public {
        try lendtroller.notifyBorrow(mToken, account) {} catch {}
    }

    function canRepay_should_succeed(address mToken, address account) public {
        try lendtroller.canRepay(mToken, account) {} catch {}
    }

    // Test Property: setTransferPaused(true) should set transferPaused = 2
    // Test Property: setTransferPause(false) should set transferPaused = 1
    // Test Preconditions: address(this) has dao permissions
    function setTransferPaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setTransferPaused(bool)", state)
        );
        if (success) {
            uint256 transferPaused = lendtroller.transferPaused();
            if (state == true) {
                assertEq(
                    transferPaused,
                    2,
                    "LENDTROLLER - setTransferPaused() true expected to set TransferPaused = 2 "
                );
            } else {
                assertEq(
                    transferPaused,
                    1,
                    "LENDTROLLER - setTransferPaused false expected to set TransferPaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setTransferPaused() expected to be successful with correct preconditions"
            );
        }
    }

    // Test Property: setSeizePaused(true) should set transferPaused = 2
    // Test Property: setTransferPause(false) should set transferPaused = 1
    // Test Preconditions: address(this) has dao permissions
    function setSeizePaused_should_succeed_with_authorized_permission(
        bool state
    ) public {
        require(centralRegistry.hasDaoPermissions(address(this)));

        (bool success, bytes memory revertData) = address(lendtroller).call(
            abi.encodeWithSignature("setSeizePaused(bool)", state)
        );
        if (success) {
            uint256 seizePaused = lendtroller.seizePaused();
            if (state == true) {
                assertEq(
                    seizePaused,
                    2,
                    "LENDTROLLER - setSeizePaused() true expected to set seizePaused = 2 "
                );
            } else {
                assertEq(
                    seizePaused,
                    1,
                    "LENDTROLLER - setSeizePaused false expected to set seizePaused = 1"
                );
            }
        } else {
            uint256 errorSelector = extractErrorSelector(revertData);
            emit LogUint256("error:", errorSelector);

            assertWithMsg(
                false,
                "LENDTROLLER - setSeizePaused() expected to be successful with correct preconditions"
            );
        }
    }

    function canLiquidate_should_succeed(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) public {
        try
            lendtroller.canLiquidate(
                dToken,
                cToken,
                account,
                amount,
                liquidateExact
            )
        {} catch {}
    }

    function canLiquidateWithExecution_should_succeed(
        address dToken,
        address cToken,
        address account,
        uint256 amount,
        bool liquidateExact
    ) public {
        try
            lendtroller.canLiquidateWithExecution(
                dToken,
                cToken,
                account,
                amount,
                liquidateExact
            )
        {} catch {}
    }

    function canSeize_should_succeed(
        address collateralToken,
        address debtToken
    ) public {
        try lendtroller.canSeize(collateralToken, debtToken) {} catch {}
    }

    function canTransfer_should_succeed(
        address mToken,
        address from,
        uint256 amount
    ) public {
        try lendtroller.canTransfer(mToken, from, amount) {} catch {}
    }

    function liquidateAccount_should_succeed(address account) public {
        try lendtroller.liquidateAccount(account) {} catch {}
    }

    function listToken_should_succeed(address token) public {
        try lendtroller.listToken(token) {} catch {}
    }

    // Stateful Functions

    // ctoken.balanceOf(user) >= collateral posted
    function cToken_balance_gte_collateral_posted(address ctoken) public {
        uint256 cTokenBalance = MockCToken(ctoken).balanceOf(address(this));

        uint256 collateralPostedForAddress = lendtroller.collateralPosted(
            address(this)
        );

        assertGte(
            cTokenBalance,
            collateralPostedForAddress,
            "LENDTROLLER - cTokenBalance must exceed collateral posted"
        );
    }

    // Market collateral posted should always be <= caps, as all values are recorded in shares rather than # of tokens
    // accountdata[address].collateralPosted <= collateral caps per token
    function collateralPosted_lte_collateralCaps(address token) public {
        uint256 collateralPosted = lendtroller.collateralPosted(token);

        uint256 collateralCaps = lendtroller.collateralCaps(token);

        assertLte(
            collateralPosted,
            collateralCaps,
            "LENDTROLLER - collateralPosted must be <= collateralCaps"
        );
    }

    // current debt > max allowed debt after folding

    // Helper Functions

    struct TokenCollateralBounds {
        uint256 collRatio;
        uint256 collReqSoft;
        uint256 collReqHard;
        uint256 liqIncSoft;
        uint256 liqIncHard;
        uint256 liqFee;
        uint256 baseCFactor;
    }

    // Bounds the specific variables required to call updateCollateralBounds
    // Variables are generated in basis points, and converted to WAD (by multiplying by 1e14)
    // Assume ALL bounds below are inclusive, on both ends
    // baseCFactor: [1, WAD/1e14]
    // liqFee: [0, MAX_LIQUIDATION_FEE/1e14]
    // liqIncSoft: [MIN_LIQUIDATION_INCENTIVE() / 1e14 + liqFee, MAX_LIQUIDATION_INCENTIVE()/1e14-1]
    // liqIncHard: [liqIncSoft+1, MAX_LIQUIDATION_INCENTIVE/1e14]
    // inherently from above, liqIncSoft < liqIncHard
    // collReqHard = [liqIncHard, MAX_COLLATERAL_REQUIREMENT()/1e14-1]
    // collReqSoft = [collReqHard+1, MAX_COLLATERAL_REQUIREMENT()/1e14]
    // collateralRatio = [0, min(MAX_COLLATERALIZATION_RATIO/1e14, (WAD*WAD)/(WAD+collReqSoft*1e14))]
    function get_safe_update_collateral_bounds(
        uint256 collRatio,
        uint256 collReqSoft,
        uint256 collReqHard,
        uint256 liqIncSoft,
        uint256 liqIncHard,
        uint256 liqFee,
        uint256 baseCFactor
    ) private returns (TokenCollateralBounds memory bounds) {
        // TODO: incorrect for new rebase (min: 10%, max: 50%)
        bounds.baseCFactor = clampBetween(baseCFactor, 1, 1e18 / 1e14);

        // liquidity incentive soft -> hard goes up
        bounds.liqFee = clampBetween(
            liqFee,
            0,
            lendtroller.MAX_LIQUIDATION_FEE() / 1e14
        );

        bounds.liqIncSoft = clampBetween(
            liqIncSoft,
            lendtroller.MIN_LIQUIDATION_INCENTIVE() / 1e14 + bounds.liqFee,
            lendtroller.MAX_LIQUIDATION_INCENTIVE() / 1e14 - 1
        );

        bounds.liqIncHard = clampBetween(
            liqIncHard,
            bounds.liqIncSoft + 1, // TODO expected changes in rebase
            lendtroller.MAX_LIQUIDATION_INCENTIVE() / 1e14
        );

        // collateral requirement soft -> hard goes down
        bounds.collReqHard = clampBetween(
            collReqHard,
            bounds.liqIncHard, // account for MIN_EXCESS_COLLATERAL_REQUIREMENT  on rebase
            lendtroller.MAX_COLLATERAL_REQUIREMENT() / 1e14 - 1
        );

        bounds.collReqSoft = clampBetween(
            collReqSoft,
            bounds.collReqHard + 1,
            lendtroller.MAX_COLLATERAL_REQUIREMENT() / 1e14
        );

        uint256 collatPremium = uint256(
            ((WAD * WAD) / (WAD + (bounds.collReqSoft * 1e14)))
        );

        if (lendtroller.MAX_COLLATERALIZATION_RATIO() > collatPremium) {
            bounds.collRatio = clampBetween(
                collRatio,
                0,
                (collatPremium / 1e14) // collat ratio is going to be *1e14, so make sure that it will not overflow
            );
            emit LogUint256(
                "collateral ratio clamped to collateralization premium:",
                bounds.collRatio
            );
        } else {
            bounds.collRatio = clampBetween(
                collRatio,
                0,
                lendtroller.MAX_COLLATERALIZATION_RATIO() / 1e14
            );
            emit LogUint256(
                "collateral ratio clamped to max collateralization ratio:",
                bounds.collRatio
            );
        }
    }

    // If the price is stale, update the round data and update lastRoundUpdate
    function check_price_feed() public {
        // if lastRoundUpdate timestamp is stale
        if (lastRoundUpdate > block.timestamp) {
            lastRoundUpdate = block.timestamp;
        }
        emit LogUint256("***********last round update: ", lastRoundUpdate);
        emit LogUint256(
            "-----------chainlink usdc",
            chainlinkUsdcUsd.latestTimestamp()
        );
        if (block.timestamp - chainlinkUsdcUsd.latestTimestamp() > 24 hours) {
            // TODO: Change this to a loop to loop over lendtroller.assetsOf()
            // Save a mapping of assets -> chainlink oracle
            // call updateRoundData on each oracle
            chainlinkUsdcUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
            chainlinkDaiUsd.updateRoundData(
                0,
                1e8,
                block.timestamp,
                block.timestamp
            );
        }
        mockUsdcFeed.setMockUpdatedAt(block.timestamp);
        mockDaiFeed.setMockUpdatedAt(block.timestamp);
        mockUsdcFeed.setMockAnswer(1e8);
        mockDaiFeed.setMockAnswer(1e8);
        lastRoundUpdate = block.timestamp;
    }
}
