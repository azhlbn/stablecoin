// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


contract IPeggedAsset {
    /// @dev Not allowed to pass zero address
    error ZeroAddress();

    /// @dev Allowed only for ADMIN and SUPER_ADMIN roles
    error OnlyForAdmin();

    /// @dev Not allowed if msg sender is blacklisted
    error Blacklisted();

    /// @dev Proposed owner must be different from the existing owner
    error OwnerMatch();

    /// @dev Msg sender is not a granted owner
    error NotGrantedOwner();
    
    /// @dev Not allowed to renounce default admin role
    error NotAllowed();

    /// @dev Transfer not allowed if amount of LP tokens less then owner's balance in tokens
    error NotEnoughCollateral();

    /// @dev The transfer or burn is not allowed if after this the balance of this owner's token falls below minOwnerBalance
    error MinOwnerBalanceCrossed();

    /// @dev Going beyond maximum deviation
    error TooLargeDeviation();

    /// @dev Max depeg reached, not allow to transfer any tokens
    error MaxDepegReached();

    event Minted(address indexed from, uint256 indexed amount);
    event Burned(address indexed from, uint256 indexed amount);
    event AddedToBlacklist(address indexed who);
    event RevomedFromBlacklist(address indexed who);
}