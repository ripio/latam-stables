# Project Audit Context

## Project Overview
The `LimitedMinter` contract is a Solidity smart contract designed to enforce daily minting limits for multiple LatamStable tokens. It allows:
- Admins of LatamStable tokens to register their tokens and set daily minting limits
- Only addresses with `MINTER_ROLE` to mint tokens, with enforcement of daily limits
- Admins to update mint destinations and daily mint limits
- Emergency pausing and unpausing of minting operations
- Protections against reentrancy attacks

The contract is intended for use in environments where strict control over token minting is required, such as stablecoin ecosystems.

## Assumptions
- The contract will be deployed on EVM-compatible chains
- LatamStable tokens implement the required interface (`hasRole`, `DEFAULT_ADMIN_ROLE`, `mint`)
- Only trusted admins will be granted the ability to register/unregister tokens and update configurations
- The contract will be managed by entities familiar with smart contract security best practices
- The contract may be paused in emergencies by an admin
- The contract will interact with external token contracts that follow OpenZeppelin's AccessControl patterns

## Audit Scope
The audit should focus on the `LimitedMinter.sol` contract, specifically examining:
- Token registration and unregistration logic
- Daily minting limit enforcement
- Access control and role management
- Minting process and destination management
- Emergency pause/unpause functionality
- Reentrancy protections

## Key Areas to Focus
1. Correct enforcement of daily minting limits per token
2. Access control and permission management for admin and minter roles
3. Input validation for token addresses, mint amounts, and configuration updates
4. Reentrancy and pause protections
5. Proper event emission for state changes
6. Gas optimization opportunities
7. Handling of edge cases (e.g., re-registering tokens, zero addresses)

## Recent Changes
This is the initial version of the `LimitedMinter` contract. No recent changes have been made.

## Known Issues or Concerns
1. Reliance on external token contracts for access control checks (assumes correct implementation)
2. Minting limits are enforced per 24-hour UTC day (potential for manipulation if block timestamps are not strictly enforced)
3. The `mintedPerDay` mapping persists even if a token is unregistered and re-registered
4. No mechanism for retroactive correction if a mint exceeds the daily limit due to a race condition
5. The contract assumes the external token's `mint` function is secure and does not introduce vulnerabilities

## Out of Scope
- Implementation and security of LatamStable token contracts

## Protocol Details
The contract is designed to act as a minting controller for multiple LatamStable tokens, enforcing daily minting caps and providing admin controls for configuration. It leverages OpenZeppelin's AccessControl, Pausable, and ReentrancyGuard modules for security and flexibility.

## Deployment Information
- Target Network: Any EVM-compatible network
- Solidity Version: ^0.8.27
- License: MIT

## Previous Audits
This is the first audit of the `LimitedMinter` contract.

## Additional Notes
The contract is intended for production use in stablecoin ecosystems and should be thoroughly audited for security vulnerabilities, especially around access control, minting logic, and interactions with external token contracts. The audit should also consider potential edge cases and recommend best practices for secure deployment and operation. 