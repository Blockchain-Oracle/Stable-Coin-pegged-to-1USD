// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DecentralizeStableCoin} from "../src/DecentrailizeStableCoin.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../src/mock/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployDSC;
    DecentralizeStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address wbtc;
    address weth;
    uint256 deployerKey;
    address USER = makeAddr("USER");
    address USERerc20;

    uint256 private constant COLLATERAL = 1 ether;
    uint256 private constant DSCMINTED = 1000; //$2000 == 1 eth you can have 50% of collateral

    event collateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    function setUp() public {
        deployDSC = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDSC.run();
        (wethPriceFeed, wbtcPriceFeed, wbtc, weth, deployerKey) = helperConfig.ActiveConfig();
        USERerc20 = address(deployDSC);
        vm.deal(USER, 30 ether);
        vm.deal(USERerc20, 30 ether);
    }

    ////////////////////////////
    //////////////////////////////
    //////constructor test//////
    ////////////////////////////////
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertIfTokenAddressInLengthDosentMatchPriceFeed() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(wethPriceFeed);
        priceFeedAddress.push(wbtcPriceFeed);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__TokenAddressAndPriceFeedMustBeSameLength()"));
        new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
    }

    function testGetTokenAmountFromUsd() public {
        vm.prank(USER);
        //2000
        uint256 usdAmount = 100;
        uint256 expectedWeth = 0.05 ether;
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(tokenAmount, expectedWeth);
    }

    function testGetUsdValue() public {
        uint256 usdValue = dscEngine.getUsdValue(weth, 2e18);
        assertEq(usdValue, 4000);
    }

    ////////////////////////////
    //////////////////////////////
    //////Deposit Collateral//////
    ////////////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approveInternal(address(dscEngine), USER, COLLATERAL);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__NeedsMoreThanZero(uint256)", 0));
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertIfTokenAddressDoesnotExist() public {
        ERC20Mock ran = new ERC20Mock("RAN", "RAN", USER, 100000000000000000);
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__TokenNotAllow()"));
        dscEngine.depositCollateral(address(ran), COLLATERAL);
    }

    modifier depositCollateral() {
        vm.startPrank(USERerc20);
        ERC20Mock(weth).approveInternal(address(deployDSC), address(dscEngine), COLLATERAL);
        dscEngine.depositCollateral(weth, COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier tranferSomeTokenToUser() {
        vm.startPrank(USERerc20);
        ERC20Mock(weth).approveInternal(USERerc20, USER, 2 ether);
        ERC20Mock(weth).transferInternal(USERerc20, USER, 2 ether);
        vm.stopPrank();
        _;
    }

    function testDepositCollateral() public depositCollateral {
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USERerc20);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedTotalCollateralValueInUsd = dscEngine.getUsdValue(weth, COLLATERAL);
        uint256 expectedTotalCollateralValueInEth = dscEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);
        assertEq(COLLATERAL, expectedTotalCollateralValueInEth);
    }

    function testmintDsc() public depositCollateral {
        //confirm amouunt minted
        vm.prank(USERerc20);
        dscEngine.mintDsc(DSCMINTED);
        (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(USERerc20);
        uint256 expectedTotalDSCMinted = DSCMINTED;
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
    }

    function testmintDscRevertWhenHealtIsBroken() public depositCollateral {
        vm.prank(USERerc20);

        vm.expectRevert(abi.encodeWithSignature("DSCEngine__BreaksHealthFactor(uint256)", 0));
        dscEngine.mintDsc(1002); //grater than 50% of collateral 1ether == 2000
        uint256 healthfactor = dscEngine.getHealthFactor(USERerc20);
        console.log("healthfactor", healthfactor);
    }

    function testDepositAndMintCollateralFunction() public {
        vm.startPrank(USERerc20);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL, DSCMINTED);
        vm.stopPrank();
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USERerc20);
        assertEq(totalDSCMinted, DSCMINTED);
        assertEq(totalCollateralValueInUsd, dscEngine.getUsdValue(weth, COLLATERAL));
    }

    function testReedeemCollateralFunctionErrorIfCollateralIsNotDeposited() public {
        //throws eror if collateral is not yet deposited
        vm.startPrank(USERerc20);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL);
        vm.expectRevert(); //revert trying to substract collateral from total collateral
        dscEngine.redeemCollateral(weth, COLLATERAL);
        vm.stopPrank();
    }

    function testReedeemCollateralFunctionCollateralValueAfterReedeem() public depositCollateral {
        //substract collateral from total collateral
        uint256 healthFactorBefore = dscEngine.getHealthFactor(USERerc20);
        vm.startPrank(USERerc20);
        dscEngine.redeemCollateral(weth, COLLATERAL);
        (, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(USERerc20);
        uint256 healthFactorAfter = dscEngine.getHealthFactor(USERerc20);
        console.log("healthFactorAfter", healthFactorAfter);
        console.log("healthFactorBefore", healthFactorBefore);
        vm.stopPrank();
        assertEq(totalCollateralValueInUsd, 0);
    }

    function testRedeemCollateralEmitEvent() public depositCollateral {
        //confirm emit event
        vm.prank(USERerc20);
        vm.expectEmit();
        emit collateralRedeemed(USERerc20, USERerc20, weth, COLLATERAL);
        dscEngine.redeemCollateral(weth, COLLATERAL);
    }

    function testReedmedCollateralConfirmBalance() public depositCollateral {
        //confirm the to balance

        uint256 startingBalanceOfUser = ERC20Mock(weth).balanceOf(USERerc20);
        uint256 startingBalanceOfContrac = ERC20Mock(weth).balanceOf(address(dscEngine));
        vm.prank(USERerc20);
        dscEngine.redeemCollateral(weth, COLLATERAL);
        uint256 endingBalanceOfUser = ERC20Mock(weth).balanceOf(USERerc20);
        uint256 endingBalanceOfContrac = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(startingBalanceOfContrac, COLLATERAL);
        assertEq(endingBalanceOfContrac, 0);
        assertEq(startingBalanceOfContrac + startingBalanceOfUser, endingBalanceOfUser);
    }

    function testBurnDscREVERTIfDscMintedIsZero() public {
        //REVERT IF DSC MINTED IS ZERO
        vm.expectRevert();
        dscEngine.burnDsc(2000); //dscInDollars
    }

    function testBurnDscREVERTIfNotApproved() public depositCollateral {
        //REVERT IF NOT APPROVED
        vm.startPrank(USERerc20);
        dscEngine.mintDsc(DSCMINTED);
        vm.expectRevert();
        dscEngine.burnDsc(DSCMINTED);
        vm.stopPrank();
    }

    function testBurnDscBalance() public depositCollateral {
        //CONFIRM  BALANCE OF CONTRACT AND USER
        vm.startPrank(USERerc20);
        dscEngine.mintDsc(DSCMINTED);
        uint256 startingbalanceOfUser = ERC20Mock(address(dsc)).balanceOf(USERerc20);
        IERC20(address(dsc)).approve(address(dscEngine), DSCMINTED);
        dscEngine.burnDsc(DSCMINTED);
        vm.stopPrank();
        uint256 endingbalanceOfUser = ERC20Mock(address(dsc)).balanceOf(USERerc20);
        uint256 endingbalanceOfContract = ERC20Mock(address(dsc)).balanceOf(address(dscEngine));

        assertEq(startingbalanceOfUser, DSCMINTED);
        assertEq(endingbalanceOfUser, 0);
        assertEq(endingbalanceOfContract, 0);
    }

    function testredeemCollateralForDsc() public depositCollateral {
        vm.startPrank(USERerc20);
        dscEngine.mintDsc(DSCMINTED);
        uint256 startingbalanceOfUser = ERC20Mock(address(dsc)).balanceOf(USERerc20);
        IERC20(address(dsc)).approve(address(dscEngine), DSCMINTED);
        dscEngine.redeemCollateralForDsc(weth, COLLATERAL, DSCMINTED);
        vm.stopPrank();
        assertEq(startingbalanceOfUser, DSCMINTED);
        uint256 endingbalanceOfUser = ERC20Mock(address(dsc)).balanceOf(USERerc20);
        uint256 endingbalanceOfContract = ERC20Mock(address(dsc)).balanceOf(address(dscEngine));
        assertEq(endingbalanceOfUser, 0);
        assertEq(endingbalanceOfContract, 0);
    }
    //revert if it affect benefector health factor
    //reveat if  the user health factor is not improved
    //confirm balance plus bonus
    //confirm user health factor is improved
    // confirm user benefector dsc balance
    //confirm user dsc balance

    function testLiquidates() public depositCollateral tranferSomeTokenToUser {
        vm.startPrank(USERerc20);
        dscEngine.mintDsc(DSCMINTED);
        vm.stopPrank();
        //CHANGE PRICE OF ETH FROM $2000 TO $1000
        // 1000DSC => 500DSC
        MockV3Aggregator(wethPriceFeed).updateAnswer(1100e8);
        //new price $1000
        //USERerc20 is now liquidated
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), 2 ether);
        dscEngine.depositCollateralAndMintDsc(weth, 2 ether, DSCMINTED);
        IERC20(address(dsc)).approve(address(dscEngine), DSCMINTED);
        dscEngine.liquidate(weth, USERerc20, DSCMINTED);
        //BALANCE OF USER20 ANF CONFIRM FIXED HEALTH FACTOR
        uint256 balance = dscEngine.getAmountOfDscMinted(USERerc20);
        uint256 balanceUSER = IERC20(address(dsc)).balanceOf(USER);

        (, uint256 totalcolater) = dscEngine.getAccountInformation(USERerc20);
        console.log(totalcolater);
        console.log(balance);
        uint256 healthFactor = dscEngine.getHealthFactor(USERerc20);
        vm.stopPrank();
        assertEq(balance, 0);
        assertEq(healthFactor, type(uint256).max);
        assertEq(balanceUSER, 0);
    }

    function testLiquidateRevertIfHealthFactorIsNotBelowOne() public depositCollateral tranferSomeTokenToUser {
        //CHANGE PRICE OF ETH FROM $2000 TO $1000
        // 1000DSC => 500DSC
        MockV3Aggregator(wethPriceFeed).updateAnswer(1100e8);
        //new price $1000
        //USERerc20 is now liquidated
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), 2 ether);
        dscEngine.depositCollateralAndMintDsc(weth, 2 ether, DSCMINTED);
        IERC20(address(dsc)).approve(address(dscEngine), DSCMINTED);
        vm.expectRevert(abi.encodeWithSignature("DSCEngine__HealthFactorOkay()"));
        dscEngine.liquidate(weth, USERerc20, DSCMINTED);
        vm.stopPrank();
    }
}
