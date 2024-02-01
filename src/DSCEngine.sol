// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizeStableCoin} from "./DecentrailizeStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../test/Libaries/OracleLib.sol";
/// @title DSC Engine
/// @author BlockChain Oracle
/// @notice this system is designed to be minmal as possible, and have the tokens mantain a 1 token == $1 peg
/// @dev  This Stable coin has the properties
// -Exogonous Collateral
// -dollar Pegged
// Algorithmic Stable
//it is similar to dai if dai had no goerance, no fees, and was only backed by WETH ADN WBTC

contract DSCEngine is ReentrancyGuard {
    ///////////////////////////////
    /////////////////////////////
    ///..ERROR///////////
    //////////////////////
    error DSCEngine__NeedsMoreThanZero(uint256 _amount);
    error DSCEngine__TokenAddressAndPriceFeedMustBeSameLength();
    error DSCEngine__TokenNotAllow();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFail();
    error DSCEngine__HealthFactorOkay();
    error DSCEngine__HealthFactoryNotImproved(uint256 healhFactor);

    ///////////////////////////////
    /////////////////////////////
    ///TYPES ///////////
    /////////////////////

    using OracleLib for AggregatorV3Interface;
    ///////////////////////////////
    /////////////////////////////
    ///.STate variable///////////
    /////////////////////

    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateralDeposit;
    mapping(address user => uint256 amountMintedDSC) s_DSCMinted;
    address[] private s_collateralToken;
    uint256 private constant LIQUIADTION_THRESHOLD = 50;
    uint256 private constant LIQUIADTION_PRECISION = 100;
    uint256 private constant HEALTHFACTOR = 1;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e8;
    uint256 private constant LIQUIDATION_BONUS = 10;

    DecentralizeStableCoin private immutable i_decetralizeStableCoin;

    ///////////////////////////////
    /////////////////////////////
    ///..Event///////////
    //////////////////////
    event DepositCollateral(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollteral
    );
    event collateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ///////////////////////////////
    /////////////////////////////
    ///..Modifier///////////
    //////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero(_amount);
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeed[_tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllow();
        }
        _;
    }

    ///////////////////////////////
    /////////////////////////////
    ///..constructor///////////
    //////////////////////

    constructor(address[] memory _tokenAddress, address[] memory _priceFeed, address dscAddress) {
        if (_tokenAddress.length != _priceFeed.length) {
            revert DSCEngine__TokenAddressAndPriceFeedMustBeSameLength();
        }

        for (uint256 i = 0; i < _tokenAddress.length; i++) {
            s_priceFeed[_tokenAddress[i]] = _priceFeed[i];
            s_collateralToken.push(_tokenAddress[i]);
        }
        i_decetralizeStableCoin = DecentralizeStableCoin(dscAddress);
    }

    ///////////////////////////////
    /////////////////////////////
    ///..External Functions///////////
    //////////////////////

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollteral)
        public
        moreThanZero(amountCollteral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_userCollateralDeposit[msg.sender][tokenCollateralAddress] += amountCollteral;
        emit DepositCollateral(msg.sender, tokenCollateralAddress, amountCollteral);
        bool sucess = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollteral);
        if (!sucess) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDsc(uint256 amountToMint) public nonReentrant moreThanZero(amountToMint) {
        s_DSCMinted[msg.sender] += amountToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_decetralizeStableCoin.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintFail();
        }
    }

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollteral, uint256 amountToMInt)
        public
    {
        depositCollateral(tokenCollateralAddress, amountCollteral);
        mintDsc(amountToMInt);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */

    function redeemCollateral(address tokenAddress, uint256 amountCollateral)
        public
        nonReentrant
        moreThanZero(amountCollateral)
    {
        _redeemCollateral(tokenAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice careful! You'll burn your DSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you DSC but keep your collateral in.
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */

    function redeemCollateralForDsc(address tokenAddress, uint256 amountCollateral, uint256 amountBurnDsc) external {
        burnDsc(amountBurnDsc);
        redeemCollateral(tokenAddress, amountCollateral);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * follow CEI => Cheecks effect interaction
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _getHealthFactor(user);
        if (startingHealthFactor > HEALTHFACTOR) {
            revert DSCEngine__HealthFactorOkay();
        }
        //we Want to burn thier DSC debt

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 tokenAmountFromDebtCoveredWithBonus =
            (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIADTION_PRECISION;
        uint256 totalCollateralRedeem = tokenAmountFromDebtCoveredWithBonus + tokenAmountFromDebtCovered;
        _redeemCollateral(collateral, totalCollateralRedeem, user, msg.sender);
        //900dsc + 10percent
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingHealthFactor = _getHealthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactoryNotImproved(endingHealthFactor);
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////
    /////////////////////////////
    ///..private internal Functions///////////
    /////////////////////
    function _getAccountUser(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(user);
        //can the user deposit collateral from two wrapped ether btc and eth to borrow
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        //total dsc
        //total collateral value
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd) = _getAccountUser(user);
        return _calculateHealthFactor(totalDSCMinted, totalCollateralValueInUsd);
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        //cheeck health factor
        //revert if they dont

        uint256 userHealthFactor = _getHealthFactor(user);
        if (userHealthFactor < HEALTHFACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateraAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_userCollateralDeposit[from][tokenCollateraAddress] -= amountCollateral;
        emit collateralRedeemed(from, to, tokenCollateraAddress, amountCollateral);
        bool sucess = IERC20(tokenCollateraAddress).transfer(to, amountCollateral);
        if (!sucess) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalf, address from) private {
        s_DSCMinted[onBehalf] -= amountDscToBurn;
        bool sucess = i_decetralizeStableCoin.transferFrom(from, address(this), amountDscToBurn);
        if (!sucess) {
            revert DSCEngine__TransferFailed();
        }
        i_decetralizeStableCoin.burn(amountDscToBurn);
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 totalCollateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // what i did here was percentage but in a cool way
        //rule iS always want to have 50% above of collateral

        // (1000 eth * 50 )  = 50,000/100  = $500
        // 150eth * 50 = 7500/100 = 75/DSC =  75/100 < 1 == health factor < 1
        // and remeber solidity dont use decimal
        if (totalCollateralValueInUsd == 0 && totalDSCMinted > 1) {
            uint256 collateralAdjustedForThreshold =
                (totalCollateralValueInUsd * LIQUIADTION_THRESHOLD) / LIQUIADTION_PRECISION;
            return (collateralAdjustedForThreshold) / totalDSCMinted;
        } else if ( /*totalCollateralValueInUsd == 0 */ totalDSCMinted == 0) {
            return type(uint256).max;
        } else {
            uint256 collateralAdjustedForThreshold =
                (totalCollateralValueInUsd * LIQUIADTION_THRESHOLD) / LIQUIADTION_PRECISION;
            return (collateralAdjustedForThreshold) / totalDSCMinted;
        }
    }
    ///////////////////////////////
    /////////////////////////////
    ///..public  and external view and pure Functions///////////
    //////////////////////

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 tokenCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_userCollateralDeposit[user][token];
            tokenCollateralInUsd += getUsdValue(token, amount);
        }
        return tokenCollateralInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 answer,,,) = priceFeed.stalePriceCheeckLatestRoundData();
        //1 eth = 1000
        //the returned value 1000 * 1e8;
        return (uint256(answer) * amount) / 1e26;
    }
    //converting to eth cause dsc is value in dollars the amount of dsc worth to eth

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheeckLatestRoundData();
        return (usdAmountInWei * PRECISION * ADDITIONAL_FEED_PRECISION) / uint256(price);
    }
    // 10e8

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountUser(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getAmountOfDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getCollateralToken() external view returns (address[] memory) {
        return s_collateralToken;
    }

    function getTotalCollateralOfUser(address user, address token) external view returns (uint256) {
        return s_userCollateralDeposit[user][token];
    }

    function getCollateralTokenPriceFeed(address collateral) external view returns (address) {
        return s_priceFeed[collateral];
    }
}

// 100 * 1e18 / 2000 * 1e10 = 1e26
