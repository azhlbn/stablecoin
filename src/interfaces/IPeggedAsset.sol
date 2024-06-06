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

    event Minted(address indexed from, uint256 indexed amount);
    event Burned(address indexed from, uint256 indexed amount);
    event AddedToBlacklist(address indexed who);
    event RevomedFromBlacklist(address indexed who);
}