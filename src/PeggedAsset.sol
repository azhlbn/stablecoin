// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable, IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IPeggedAsset} from "interfaces/IPeggedAsset.sol";

// todo
// + Роли с доступами:
// SUPER_ADMIN: блэклист / mint / burn / ручное восстановление пега
// ADMIN: блэклист / ручное восстановление пега
// + Blacklist. Добавленный адрес не сможет получать и отправлять токены.
// + mint/burn токенов овнером. Этим будет меняться пег.
// + ридер для отображения текущего пега. Функция будет выдавать соотношение баланса в ЛП токенах овнера и саплая новых токенов.
// + логика для ручного восстановления пега (см. edge cases)
// + добавить смену главного админа
// + добавить ограничение на отклонение пега (?)

// flow
// - деплой контракта, минт соответствующего колва токенов
// - овнер передает токены кому хочет. Может передавать/сжигать пока на балансе токенов не меньше чем установлено. 
//   Чтобы было что сжигать при колебании колва ЛП
// - овнер может сжигать и минтить токены кому хочет если отклонение пега не больше определенного значения. 
//   Это значение может быть установлено овнером.
// - пользователи могут передавать токены если они не в блэклисте. В блэклист может добавить любой админ. Только овнер назначает роли.
// - пользователи могут передавать токены если отклонение пэга в большую сторону не больше определенного значения. 
//   То есть пока их обеспечение достаточное
// - вызов функции sync может делать любой. Эта функция контролирует саплай токена. 
//   Если нужно доминтить токены, они доминчиваются на адрес овнера. 
//   Если нужно сжечь, они сжигаются у овнера. 
//   Если не достаточно токенов на балансе овнера, то сжигается столько сколько у него есть на балансе.
// - функция sync вызывается ораклом при наличии отслеживаемых эвентов в ЛП контракте.
// - при недостаточной обеспеченности отключается возможность минтить больше токенов овнером

contract PeggedAsset is IPeggedAsset, Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    uint256 public constant PEG_PRECISION = 1e18;

    IERC20 public trackedToken;
    address public owner;

    // peg deviation
    int256 public deviation;
    uint256 public maxDeviation;

    uint256 public minOwnerBalance;
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

        // by default equal to 50% of initial supply
        minOwnerBalance = trackedToken.balanceOf(owner) / 2;

        // by default equal to 10% of initial supply
        maxDepeg = trackedToken.balanceOf(owner) / 10;

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(SUPER_ADMIN, owner);
    }

    modifier onlyAdmin() {
        if (!hasRole(SUPER_ADMIN, msg.sender) && !hasRole(ADMIN, msg.sender)) revert OnlyForAdmin();
        _;
    }

    modifier checkDeviation(int256 value) {
        if (deviation + value > int256(maxDeviation) || deviation + value < -int256(maxDeviation)) revert TooLargeDeviation();
        _;
    }

    modifier checkOwnerBalance(address from, uint256 value) {
        if (from == owner && balanceOf(owner) - value < minOwnerBalance) revert MinOwnerBalanceCrossed();
        _;
    }

    /// PUBLIC LOGIC

    /// @dev Peg adjusting
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

    function transfer(address to, uint256 value) public override checkOwnerBalance(msg.sender, value) returns (bool) {
        if (hasRole(BLACKLISTED, msg.sender)) revert Blacklisted();
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        if (trackedTokenBalance < totalSupply() && totalSupply() - trackedTokenBalance > maxDepeg) revert MaxDepegReached();
        return super.transfer(to, value);
    } 

    function transferFrom(address from, address to, uint256 value) public override checkOwnerBalance(from, value) returns (bool) {
        if (hasRole(BLACKLISTED, from)) revert Blacklisted();
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        if (trackedTokenBalance < totalSupply() && totalSupply() - trackedTokenBalance > maxDepeg) revert MaxDepegReached();
        return super.transferFrom(from, to, value);
    }

    /// SUPER ADMIN LOGIC

    function mint(address who, uint256 amount) public onlyRole(SUPER_ADMIN) checkDeviation(int256(amount)) {
        _updatePeg(int256(amount));
        _mint(who, amount);
        emit Minted(who, amount);
    }

    function burn(address who, uint256 amount) public onlyRole(SUPER_ADMIN) checkOwnerBalance(who, amount) checkDeviation(-int256(amount)) {
        _updatePeg(-int256(amount));
        _burn(who, amount);
        emit Burned(who, amount);
    }

    function setMaxDeviation(uint256 value) external onlyRole(SUPER_ADMIN) {
        maxDeviation = value;
    }

    function setMinOwnerBalance(uint256 value) external onlyRole(SUPER_ADMIN) {
        minOwnerBalance = value;
    }

    function setMaxDegep(uint256 value) external onlyRole(SUPER_ADMIN) {
        maxDepeg = value;
    }

    /// ADMIN LOGIC

    function addToBlacklist(address who) external onlyAdmin {
        if (who == address(0)) revert ZeroAddress();
        _grantRole(BLACKLISTED, who);
        emit AddedToBlacklist(who);
    }

    function removeFromBlacklist(address who) external onlyAdmin {
        if (who == address(0)) revert ZeroAddress();
        _revokeRole(BLACKLISTED, who);
        emit RevomedFromBlacklist(who);
    }

    /// OWNER CHANGE LOGIC

    /// @notice Propose a new owner
    /// @param _newOwner New contract owner
    function grantOwnership(address _newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newOwner == address(0)) revert ZeroAddress();
        if (hasRole(DEFAULT_ADMIN_ROLE, _newOwner)) revert OwnerMatch();

        _grantedOwner = _newOwner;
    }

    /// @notice Claim ownership by granted address
    function claimOwnership() external {
        if (_grantedOwner != msg.sender) revert NotGrantedOwner();
        _grantRole(DEFAULT_ADMIN_ROLE, _grantedOwner);
        _revokeRole(DEFAULT_ADMIN_ROLE, owner);
        
        // move the treasury form the old owner to the new one
        trackedToken.transfer(_grantedOwner, trackedToken.balanceOf(owner));
        
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

    function _updatePeg(int256 amount) internal {
        unchecked { deviation += int256(amount); }
    }

    /// READERS

    /// @notice Current peg deviation
    function currentPeg() external view returns (uint256) {
        uint256 trackedTokenBalance = trackedToken.balanceOf(owner);
        return uint256(int256(trackedTokenBalance) + deviation) * PEG_PRECISION / trackedTokenBalance;
    }
}