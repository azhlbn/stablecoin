// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// todo
// - Роли с доступами:
// SUPER_ADMIN: блэклист / mint / burn / ручное восстановление пега
// ADMIN: блэклист / ручное восстановление пега
// - Blacklist. Добавленный адрес не сможет получать и отправлять токены.
// - mint/burn токенов овнером. Этим будет меняться пег.
// - ридер для отображения текущего пега. Функция будет выдавать соотношение баланса в ЛП токенах овнера и саплая новых токенов.
// - логика для ручного восстановления пега (см. edge cases)

contract PeggedAsset is Initializable, ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin, 
        string memory tokenName,
        string memory tokenSymbol
    ) initializer public {
        __ERC20_init(tokenName, tokenSymbol);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    function mint(address to, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyRole(SUPER_ADMIN) {
        _burn(to, amount);
    }
}