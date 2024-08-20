// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20Upgradeable, IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IPeggedAsset } from "interfaces/IPeggedAsset.sol";
import { IUniswapV2Router01 } from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import { IUniswapV2Pair } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";


contract PeggedAsset is IPeggedAsset, Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    IUniswapV2Router01 public router;
    IUniswapV2Pair public pair;

    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    uint256 public constant PEG_PRECISION = 1e18;

    address public owner;
    IERC20 public tokenA;
    IERC20 public tokenB;

    // peg deviation params
    int256 public deviation;
    uint256 public maxDeviation;

    // slippage params equal to zero by default
    uint256 amountAMin;
    uint256 amountBMin;

    address internal _grantedOwner;

    uint8 private _dec;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner, 
        string memory tokenName,
        string memory tokenSymbol,
        address _tokenA,
        address _tokenB,
        address _router,
        uint8 _decimals
    ) initializer public {
        __ERC20_init(tokenName, tokenSymbol);
        __AccessControl_init();

        if (
            address(_tokenA) == address(0) || 
            address(_tokenB) == address(0) ||
            initialOwner == address(0)
        ) revert ZeroAddress();

        owner = initialOwner;       
        _dec = _decimals;

        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        router = IUniswapV2Router01(_router);

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(SUPER_ADMIN, owner);
    }

    modifier onlyAdmin() {
        if (!hasRole(SUPER_ADMIN, msg.sender) && !hasRole(ADMIN, msg.sender)) revert OnlyForAdmin();
        _;
    }

    /// PUBLIC LOGIC

    /// @dev Add liquidity to uniswap v2
    /// @param usdcAmount Amount of USDC tokens to add. USDT will be calculated automatically
    function addLiquidity(uint256 usdcAmount) external returns (uint256 addedA, uint256 addedB, uint256 liquidity) {
        uint256 usdtAmount = usdcAmount;

        if (address(pair) != address(0)) {
            (uint112 reserveA, uint112 reserveB, ) = pair.getReserves();
            usdtAmount = router.quote(usdcAmount, reserveA, reserveB);
        }

        if (
            tokenA.balanceOf(msg.sender) < usdcAmount || 
            tokenB.balanceOf(msg.sender) < usdtAmount
        ) revert NotEnoughTokensToAdd();

        tokenA.transferFrom(msg.sender, address(this), usdcAmount);
        tokenB.transferFrom(msg.sender, address(this), usdtAmount);

        tokenA.approve(address(router), usdcAmount);
        tokenB.approve(address(router), usdtAmount);
        
        // adding liquidity to uni v2 pool
        (addedA, addedB, liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            usdcAmount,
            usdtAmount,
            amountAMin,
            amountBMin,
            address(this),
            block.timestamp + 20 * 60 // 20 min
        );

        // minting tokens in amount equal to doubled LP 
        _mint(address(this), liquidity * 2);

        // update pair address if it is first liquidity adding
        if (address(pair) == address(0)) {
            address factory = router.factory();
            pair = IUniswapV2Pair(IUniswapV2Factory(factory).getPair(address(tokenA), address(tokenB)));
        }

        // return the surplus back to the user
        if (addedA < usdcAmount) tokenA.transfer(msg.sender, usdcAmount - addedA);
        if (addedB < usdtAmount) tokenB.transfer(msg.sender, usdtAmount - addedB);

        emit LiquidityAdded(msg.sender, liquidity);
    }

    /// @dev Remove liquidity from uniswap v2
    function removeLiquidity(uint256 burnAmount) external returns(uint256 amountA, uint256 amountB) {
        uint256 liquidityToRemove = burnAmount / 2;

        if (balanceOf(msg.sender) < burnAmount) revert NotEnoughTokensToBurn();
        if (liquidityToRemove > pair.balanceOf(address(this))) revert NotEnoughLiquidityBalance();

        _burn(msg.sender, burnAmount);

        pair.approve(address(router), liquidityToRemove);

        (amountA, amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidityToRemove,
            amountAMin,
            amountBMin,
            address(this),
            block.timestamp + 20 * 60
        );

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, burnAmount);
    }

    /// @dev Increase liquidity and mint tokens without adding liquidity to pool
    function addLP(uint256 liquidity) external {
        if (address(pair) == address(0)) {
            address factory = router.factory();
            pair = IUniswapV2Pair(IUniswapV2Factory(factory).getPair(address(tokenA), address(tokenB)));
        }
        if (pair.balanceOf(msg.sender) < liquidity) revert NotEnoughLPToAdd();
        pair.transferFrom(msg.sender, address(this), liquidity);
        _mint(address(this), liquidity * 2);
        emit LPAdded(msg.sender, liquidity);
    }

    /// @dev Overrided transfer with validity checks
    function transfer(address to, uint256 value) public override returns (bool) {
        if (hasRole(BLACKLISTED, msg.sender)) revert Blacklisted();
        return super.transfer(to, value);
    } 

    /// @dev Overrided transferFrom with validity checks
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (hasRole(BLACKLISTED, msg.sender)) revert Blacklisted();
        return super.transferFrom(from, to, value);
    }

    /// SUPER ADMIN LOGIC 

    /// @dev Transfer tokens from contract's balance
    function issue(address to, uint256 value) external onlyRole(SUPER_ADMIN) {
        if (balanceOf(address(this)) < value) revert NotEnoughTokensToIssue();
        if (!this.transfer(to, value)) revert IssueFailed();
    }

    /// @dev Mint tokens by SUPER_ADMIN witch peg affecting
    function mint(address who, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _updatePeg(int256(amount));
        _mint(who, amount);
        emit Minted(who, amount);
    }

    /// @dev Burn tokens by SUPER_ADMIN witch peg affecting
    ///      Also owner's balance checks on not crossing the min balance
    function burn(address who, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _updatePeg(-int256(amount));
        _burn(who, amount);
        emit Burned(who, amount);
    }

    /// @dev Set param which is restrict the max token balance deviation
    function setMaxDeviation(uint256 value) external onlyRole(SUPER_ADMIN) {
        maxDeviation = value;
    }

    /// ADMIN LOGIC

    /// @dev Add address to blacklist by any admin
    function addToBlacklist(address who) external onlyAdmin {
        if (who == address(0)) revert ZeroAddress();
        _grantRole(BLACKLISTED, who);
        emit AddedToBlacklist(who);
    }

    /// @dev Remove address from blacklist by any admin
    function removeFromBlacklist(address who) external onlyAdmin {
        if (who == address(0)) revert ZeroAddress();
        _revokeRole(BLACKLISTED, who);
        emit RevomedFromBlacklist(who);
    }

    /// @dev Set slippage params for adding and removing liquidity
    function setSlippageParams(uint256 _amountAMin, uint256 _amountBMin) external onlyAdmin {
        if (amountAMin == _amountAMin && amountBMin == _amountBMin) revert SameSlippageParams();
        (amountAMin, amountBMin) = (_amountAMin, _amountBMin);
    }

    /// OWNER CHANGE LOGIC

    /// @notice Propose a new owner
    function grantOwnership(address _newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newOwner == address(0)) revert ZeroAddress();
        if (hasRole(DEFAULT_ADMIN_ROLE, _newOwner)) revert OwnerMatch();

        _grantedOwner = _newOwner;
    }

    /// @notice Claim ownership by granted address
    function claimOwnership() external {
        if (_grantedOwner != msg.sender) revert NotGrantedOwner();
        _grantRole(DEFAULT_ADMIN_ROLE, _grantedOwner);
        _grantRole(SUPER_ADMIN, _grantedOwner);
        _revokeRole(DEFAULT_ADMIN_ROLE, owner);
        _revokeRole(SUPER_ADMIN, owner);
        
        owner = _grantedOwner;
        _grantedOwner = address(0);
    }

    /// @notice The ability to refuse a DEFAULT_ADMIN_ROLE is disabled
    function revokeRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        if (role == DEFAULT_ADMIN_ROLE) revert NotAllowed();
        super.revokeRole(role, account);
    }

    /// @notice The ability to refuse a DEFAULT_ADMIN_ROLE is disabled
    function renounceRole(bytes32 role, address callerConfirmation) public override {
        if (hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAllowed();
        super.renounceRole(role, callerConfirmation);
    }

    /// INTERNAL LOGIC

    function _updatePeg(int256 value) internal {
        if (
            deviation + value > int256(maxDeviation) || 
            deviation + value < -int256(maxDeviation)
        ) revert TooLargeDeviation();
        unchecked { deviation += int256(value); }
    }

    /// READERS

    /// @dev Current peg deviation
    function currentPeg() external view returns (uint256) {
        uint256 targetBalance = pair.balanceOf(address(this)) * 2;
        return uint256(int256(totalSupply()) + deviation) * PEG_PRECISION / targetBalance;
    }

    function decimals() public override view returns (uint8) {
        return _dec;
    }
}