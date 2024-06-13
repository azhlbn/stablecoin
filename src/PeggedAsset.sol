// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable, IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IPeggedAsset} from "interfaces/IPeggedAsset.sol";


contract PeggedAsset is IPeggedAsset, Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    uint256 public constant PEG_PRECISION = 1e18;
    uint256 public constant SHARE_PRECISION = 10000;

    IERC20 public trackedToken;
    address public owner;

    // peg deviation params
    int256 public deviation;
    uint256 public maxDeviation;

    uint256 public minOwnerBalance; // share of the balance of LP tokens
    uint256 public maxDepeg;

    address internal _grantedOwner;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 trackedTokenAddress,
        address initialOwner, 
        string memory tokenName,
        string memory tokenSymbol
    ) initializer public {
        __ERC20_init(tokenName, tokenSymbol);
        __AccessControl_init();

        if (address(trackedTokenAddress) == address(0)) revert ZeroAddress();
        if (initialOwner == address(0)) revert ZeroAddress();

        trackedToken = trackedTokenAddress;
        owner = initialOwner;        

        // initial supply
        _mint(owner, trackedToken.balanceOf(owner));

        // by default equal to 10% of initial supply
        maxDeviation = trackedToken.balanceOf(owner) / 10;

        // by default equal to 50%
        minOwnerBalance = 5000;

        // by default equal to 10% of initial supply
        maxDepeg = trackedToken.balanceOf(owner) / 10;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(SUPER_ADMIN, owner);
    }

    modifier onlyAdmin() {
        if (!hasRole(SUPER_ADMIN, msg.sender) && !hasRole(ADMIN, msg.sender)) revert OnlyForAdmin();
        _;
    }

    /// PUBLIC LOGIC

    /// @dev Synchronization of balances
    function sync() public {
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        int256 targetSupply = int256(trackedTokenBalance) + deviation;

        uint256 supply = totalSupply();
        if (targetSupply < int256(supply)) {
            uint256 forBurn = uint256(int256(supply) - targetSupply);
            // burn full owner's token balance if not enough tokens for burn
            if (balanceOf(owner) < forBurn) _burn(owner, balanceOf(owner));
            else _burn(owner, uint256(int256(supply) - targetSupply));
        } else if (targetSupply > int256(supply)) {
            _mint(owner, uint256(targetSupply - int256(supply)));
        }
    }

    /// @dev Overrided transfer with validity checks
    function transfer(address to, uint256 value) public override returns (bool) {
        _checkValidity(msg.sender, value);
        return super.transfer(to, value);
    } 

    /// @dev Overrided transferFrom with validity checks
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _checkValidity(from, value);
        return super.transferFrom(from, to, value);
    }

    /// SUPER ADMIN LOGIC

    /// @dev Mint tokens by SUPER_ADMIN witch peg affecting
    function mint(address who, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _updatePeg(int256(amount));
        _mint(who, amount);
        emit Minted(who, amount);
    }

    /// @dev Burn tokens by SUPER_ADMIN witch peg affecting
    ///      Also owner's balance checks on not crossing the min balance
    function burn(address who, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _checkOwnerBalance(who, amount);
        _updatePeg(-int256(amount));
        _burn(who, amount);
        emit Burned(who, amount);
    }

    /// @dev Set param which is restrict the max token balance deviation
    function setMaxDeviation(uint256 value) external onlyRole(SUPER_ADMIN) {
        maxDeviation = value;
    }

    /// @dev Set param for minimum owner's token balance restriction
    function setMinOwnerBalance(uint256 share) external onlyRole(SUPER_ADMIN) {
        minOwnerBalance = share;
    }

    /// @dev Set param that control maximum margin of token balance from tracked token balance
    function setMaxDepeg(uint256 value) external onlyRole(SUPER_ADMIN) {
        maxDepeg = value;
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

    function _checkValidity(address from, uint256 value) internal view {
        // chack if blacklisted
        if (hasRole(BLACKLISTED, msg.sender)) revert Blacklisted();

        // check owner balance
        _checkOwnerBalance(from, value);

        // check max depeg
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        if (
            trackedTokenBalance < totalSupply() && 
            totalSupply() - trackedTokenBalance > maxDepeg
        ) revert MaxDepegReached();
    }

    function _checkOwnerBalance(address from, uint256 value) internal view {
        if (
            from == owner && balanceOf(owner) - value < 
            trackedToken.balanceOf(owner) * minOwnerBalance / SHARE_PRECISION
        ) revert MinOwnerBalanceCrossed();
    }

    /// READERS

    /// @dev Current peg deviation
    function currentPeg() external view returns (uint256) {
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        return uint256(int256(trackedTokenBalance) + deviation) * PEG_PRECISION / trackedTokenBalance;
    }

    /// @dev Check if balances updated
    function ok() external view returns (bool) {
        return int256(trackedToken.balanceOf(owner)) + deviation == int256(totalSupply());
    }
}