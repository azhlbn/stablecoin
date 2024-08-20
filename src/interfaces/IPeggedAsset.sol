// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


contract IPeggedAsset {
    event Minted(address indexed from, uint256 indexed amount);
    event Burned(address indexed from, uint256 indexed amount);
    event AddedToBlacklist(address indexed who);
    event RevomedFromBlacklist(address indexed who);
    event LiquidityAdded(address indexed sender, uint256 indexed liquidity);
    event LiquidityRemoved(address indexed sender, uint256 indexed burnAmount);
    event LPAdded(address indexed sender, uint256 indexed liquidity);

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

    /// @dev Going beyond maximum deviation
    error TooLargeDeviation();

    /// @dev User hasn't enough tokens to add
    error NotEnoughTokensToAdd();

    /// @dev User hasn't enough tokens to burn
    error NotEnoughTokensToBurn();

    /// @dev Not enough LP tokens on contract balance to remove liquidity from uni v2 pool
    error NotEnoughLiquidityBalance();

    /// @dev Not enough tokens to transfer from contract address
    error NotEnoughTokensToIssue();

    /// @dev Issue ended with fail
    error IssueFailed();

    /// @dev User hasn't enough LP tokens on balance
    error NotEnoughLPToAdd();

    /// @dev Slippage params should be differ from previous
    error SameSlippageParams();
}