## Pegged Asset
A contract representing an ERC20 standard token. The token supply will reflect the supply of the LP token specified during deployment on one of the decentralized exchanges. The peg will be maintained using an oracle and a `sync()` function, which can be called either automatically or manually. The contract uses two roles for access to functionality and includes the capability to add addresses to a blacklist. Additionally, the manager can influence the token's peg relative to the LP token through minting and burning.

### The functionality

SUPER_ADMIN role:
- `mint` 
- `burn` 
- `setMaxDeviation`
- `setMinOwnerBalance`
- `setMaxDepeg` 

ADMIN role:
- `addToBlacklist`
- `removeFromBlacklist`

Without role:
ERC20 functionality