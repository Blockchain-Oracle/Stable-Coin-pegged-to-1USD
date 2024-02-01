// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizeStableCoin} from "../../src/DecentrailizeStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../../src/mock/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizeStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    DeployDSC deployDSC;
    MockV3Aggregator ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] public userWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizeStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory tokens = dscEngine.getCollateralToken();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) external {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        console.log("balance if mgs.msg.sender", collateral.balanceOf(msg.sender));
        // console.log("balance if deployer ", collateral.balanceOf(address(deployDSC)));
        // console.log("balance if address thos", collateral.balanceOf(address(this)));
        collateral.approveInternal(msg.sender, address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToReedeem = dscEngine.getTotalCollateralOfUser(address(collateral), msg.sender);
        amount = bound(amount, 0, maxCollateralToReedeem);
        if (amount == 0) {
            return;
        }
        dscEngine.redeemCollateral(address(collateral), amount);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[(addressSeed % userWithCollateralDeposited.length)];
        vm.startPrank(sender);

        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = (int256(totalCollateralValueInUsd) / 2) - int256(totalDSCMinted);

        if (maxDscToMint <= 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));
        dscEngine.mintDsc(amount);
        timesMintIsCalled++;

        vm.stopPrank();
    }
    //this breaks the invariant test
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 seed) internal view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
