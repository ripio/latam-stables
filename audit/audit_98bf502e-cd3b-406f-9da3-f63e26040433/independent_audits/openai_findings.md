# Individual Audit Report - openai

**Audit ID:** 98bf502e-cd3b-406f-9da3-f63e26040433
**Generated:** 2025-12-31 00:26:11
**LLM:** openai

## Summary

Total findings: 7

## Findings

### Finding 1

**Contract_Name:** BridgeDeposit

**Title:** Fee collection and burn use two different mechanisms, risking inconsistent behavior with non‑standard tokens

**Description:** In `depositForBridge`, the fee is collected using `IERC20(token).safeTransferFrom`, while the remainder is burned using `ILatamStableBurnable(token).burnFrom`. This assumes the token behaves consistently for both ERC20 `transferFrom` and `burnFrom` (which itself usually calls `transferFrom` internally).

If a non‑standard or malicious token is registered (e.g., one that behaves differently for `transferFrom` vs `burnFrom`, or that charges transfer fees, or that has non‑standard allowance semantics), the following issues can arise:
- The fee transfer succeeds but `burnFrom` reverts (or vice versa), leading to partial state changes on the token side (e.g., fee moved but no burn) even though the bridge transaction reverts.
- A fee‑on‑transfer token could reduce the actual amount received by `feeCollector`, while `amountToBurn` is still computed as `amount - fixedFee`, breaking the intended conservation and accounting assumptions.

The project context states that only LatamStable tokens (OpenZeppelin‑based) are expected, but this is not enforced on‑chain. If an admin mistakenly registers a non‑LatamStable token, the bridge invariants (burned == minted + fees) may not hold.

This is primarily a trust/assumption issue rather than a direct exploit, but it can lead to accounting discrepancies and unexpected failures if assumptions are violated.

**Severity:** Medium

**Location:** {'file': 'BridgeDeposit.sol', 'line': 640, 'code_snippet': '        // Transfer fee to feeCollector\n        if (route.fixedFee > 0) {\n            if (feeCollector == address(0)) revert ZeroAddress();\n            IERC20(token).safeTransferFrom(msg.sender, feeCollector, route.fixedFee);\n            totalFeesCollected[token][destChainId] += route.fixedFee;\n        }\n\n        // Burn the rest\n        ILatamStableBurnable(token).burnFrom(msg.sender, amountToBurn);'}

**Swc:** SWC-132

**Recommendation:** Enforce at the contract level that only LatamStable tokens can be used:
- Add an interface check in `setBridgeRoutes` (and/or in `depositForBridge`) that verifies the token supports the expected LatamStable interface (e.g., via `IERC165` or by attempting a `hasRole(DEFAULT_ADMIN_ROLE, ...)` call and reverting on failure).
- Alternatively, add a dedicated `registerToken` function in `BridgeDeposit` that is callable only by the token's `DEFAULT_ADMIN_ROLE` (similar to `LimitedMinter` / `LimitedMinterBridge`), and store a whitelist of allowed tokens. `setBridgeRoutes` should then require the token to be registered.
- Document clearly in NatSpec that only LatamStable‑compliant tokens are supported and that fee‑on‑transfer or non‑standard tokens will break invariants.

If you want stronger safety, consider:
- Using a single mechanism for both fee and burn (e.g., always `burnFrom` the full `amount` and then `mint` the fee to `feeCollector` on the same token, if the token supports minting by the bridge), or
- Explicitly rejecting fee‑on‑transfer tokens by checking `balanceOf(feeCollector)` before and after the transfer and reverting if the delta != `fixedFee`.

---

### Finding 2

**Contract_Name:** BridgeDeposit

**Title:** Lack of explicit check that BridgeDeposit has MINTER_ROLE on LimitedMinterBridge can cause operational DoS

**Description:** The `fulfillBridgeMint` function assumes that this contract has the `MINTER_ROLE` on the `LimitedMinterBridge` contract so that `limitedMinter.mintTo(token, to, amount)` succeeds. If the role is not granted (or later revoked), all bridge fulfillments will revert, effectively causing a denial of service for inbound bridging on that chain.

This is mentioned in comments but not enforced on‑chain:

```solidity
/// @dev Admin must ensure this contract has MINTER_ROLE on the new LimitedMinterBridge.
```

Given the critical nature of bridging, relying solely on off‑chain operational discipline is brittle. A misconfigured deployment or upgrade could silently break the bridge until noticed.

While this is not a direct exploit (an attacker cannot gain funds), it is a significant availability risk.

**Severity:** Low

**Location:** {'file': 'BridgeDeposit.sol', 'line': 705, 'code_snippet': '        // Mint to recipient via LimitedMinterBridge (enforces per-day limits)\n        limitedMinter.mintTo(token, to, amount);'}

**Swc:** SWC-105

**Recommendation:** Add an explicit sanity check when updating the `limitedMinter` reference and optionally before minting:

1) In `updateLimitedMinter`:
```solidity
function updateLimitedMinter(ILimitedMinterBridge newMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (address(newMinter) == address(0)) revert ZeroAddress();

    // sanity check: this contract must have MINTER_ROLE on newMinter
    bytes32 minterRole = newMinter.MINTER_ROLE();
    if (!newMinter.hasRole(minterRole, address(this))) {
        revert TokenNotRegisteredInMinter(); // or a dedicated error like MissingMinterRole();
    }

    address old = address(limitedMinter);
    limitedMinter = newMinter;

    emit LimitedMinterUpdated(old, address(newMinter));
}
```

2) Optionally, add a view helper `checkMinterRole()` that operators can call to verify configuration.

Also, document in deployment runbooks that any change to `limitedMinter` must be accompanied by granting `MINTER_ROLE` to `BridgeDeposit`.

---

### Finding 3

**Contract_Name:** BridgeDeposit

**Title:** Route configuration does not validate that token is registered in LimitedMinterBridge, risking misconfigured routes

**Description:** Outbound routes in `BridgeDeposit` are configured independently of token registration in `LimitedMinterBridge`:

```solidity
mapping(address => mapping(uint256 => RouteConfig)) public routeConfigs;
...
function setBridgeRoutes(address token, uint256[] calldata destChainIds, bool enabled, uint256 fixedFee)
```

There is no on‑chain check that:
- The `token` is registered in `LimitedMinterBridge` on the destination chain, or
- Even on the current chain, that `limitedMinter.tokenConfigs(token)` exists when configuring outbound routes.

This can lead to:
- Admin enabling a route in `BridgeDeposit` for a token that is not registered in `LimitedMinterBridge` on the destination chain. Users can deposit and burn tokens, but fulfillments on the destination chain will revert with `TokenNotRegisteredInMinter`, causing stuck funds from the user's perspective until operators manually refund off‑chain.

The context notes this as a known operational risk, but it is not enforced on‑chain. Given the importance of bridging, adding at least partial on‑chain validation can reduce misconfiguration risk.

**Severity:** Low

**Location:** {'file': 'BridgeDeposit.sol', 'line': 573, 'code_snippet': '    function setBridgeRoutes(\n        address token,\n        uint256[] calldata destChainIds,\n        bool enabled,\n        uint256 fixedFee\n    ) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        if (token == address(0)) revert ZeroAddress();\n\n        for (uint256 i = 0; i < destChainIds.length; ) {\n            if (destChainIds[i] == block.chainid) revert InvalidSourceChain();\n            routeConfigs[token][destChainIds[i]] = RouteConfig({\n                enabled: enabled,\n                fixedFee: fixedFee\n            });\n            unchecked { ++i; }\n        }\n\n        emit BridgeRoutesUpdated(token, destChainIds, enabled, fixedFee);\n    }'}

**Swc:** SWC-107

**Recommendation:** While you cannot check remote‑chain configuration on‑chain, you can reduce misconfiguration risk by:

1) On the source chain, require that the token is registered in the local `LimitedMinterBridge` before enabling routes:
```solidity
(uint256 dailyMaxMint, bool exists) = limitedMinter.tokenConfigs(token);
if (!exists) revert TokenNotRegisteredInMinter();
```

2) Optionally, add an explicit `registerBridgeToken` function in `BridgeDeposit` that must be called by the token's `DEFAULT_ADMIN_ROLE` before any routes can be set. `setBridgeRoutes` would then require the token to be registered.

3) Provide operational tooling or scripts that compare `routeConfigs` on source chain with `tokenConfigs` on destination chain (off‑chain) and alert on inconsistencies.

4) Document clearly that enabling a route in `BridgeDeposit` without configuring the corresponding token in `LimitedMinterBridge` on the destination chain will cause fulfillments to fail.

---

### Finding 4

**Contract_Name:** BridgeDeposit

**Title:** Fee accounting does not expose per-route fee configuration or totals in a structured way for off-chain monitoring

**Description:** The contract tracks `totalFeesCollected[token][destChainId]` and `routeConfigs[token][destChainId].fixedFee`, but there are no dedicated view functions to enumerate or query all configured routes and their fees. Off‑chain monitoring must either:
- Know the set of tokens and chain IDs out‑of‑band, or
- Parse all historical `BridgeRoutesUpdated` and `RouteFeeUpdated` events.

While this is not a security bug, it makes it harder to build robust monitoring and reconciliation tools, which are critical for a bridge and fee system. Poor observability can delay detection of misconfigurations or anomalies (e.g., incorrect fee set, unexpected fee growth).

**Severity:** Informational

**Location:** {'file': 'BridgeDeposit.sol', 'line': 548, 'code_snippet': '    mapping(address => mapping(uint256 => RouteConfig)) public routeConfigs;\n...\n    mapping(address => mapping(uint256 => uint256)) public totalFeesCollected;'}

**Swc:** 

**Recommendation:** Add helper view functions to improve observability, for example:

```solidity
function getRouteConfig(address token, uint256 destChainId)
    external
    view
    returns (bool enabled, uint256 fixedFee, uint256 totalFees)
{
    RouteConfig memory cfg = routeConfigs[token][destChainId];
    enabled = cfg.enabled;
    fixedFee = cfg.fixedFee;
    totalFees = totalFeesCollected[token][destChainId];
}
```

Optionally, maintain an enumerable list of tokens and/or chain IDs for which routes exist (using `EnumerableSet`) so that off‑chain indexers can more easily discover all active routes.

Also ensure that operational dashboards consume `BridgeDepositInitiated` events (which already include the `fee` field) and reconcile them against `totalFeesCollected`.

---

### Finding 5

**Contract_Name:** LimitedMinter

**Title:** Lack of explicit check that LimitedMinter has MINTER_ROLE on token can cause silent operational failures

**Description:** The `mint` function in `LimitedMinter` assumes that this contract has the `MINTER_ROLE` on the external token (`ILatamStableToken(token).mint`). If that role is not granted or is later revoked, calls to `mint` will revert inside the token contract. This will manifest as a generic revert to callers, without a clear on‑chain indication that the role is misconfigured.

Given that `LimitedMinter` is a core minting component with daily limits, misconfiguration of roles can cause prolonged downtime or confusion.

This is similar in nature to the `BridgeDeposit` / `LimitedMinterBridge` role dependency.

**Severity:** Informational

**Location:** {'file': 'LimitedMinter.sol', 'line': 292, 'code_snippet': '        ILatamStableToken(token).mint(config.mintDestination, mintAmount);'}

**Swc:** SWC-105

**Recommendation:** Add a sanity check path for admins to verify configuration:

1) Add a view function:
```solidity
function hasMinterRoleOnToken(address token) external view returns (bool) {
    return ILatamStableToken(token).hasRole(ILatamStableToken(token).MINTER_ROLE(), address(this));
}
```

2) Optionally, in `registerToken`, perform a best‑effort check that this contract has `MINTER_ROLE` on the token and revert if not, or at least emit a warning event.

3) Document in deployment runbooks that whenever a token is registered with `LimitedMinter`, the token's `MINTER_ROLE` must be granted to the `LimitedMinter` contract.

---

### Finding 6

**Contract_Name:** LimitedMinterBridge

**Title:** Lack of explicit check that LimitedMinterBridge has MINTER_ROLE on token can cause silent operational failures

**Description:** Similar to `LimitedMinter`, `LimitedMinterBridge.mintTo` assumes that this contract has `MINTER_ROLE` on the external token (`ILatamStableToken(token).mint`). If the role is not granted or is revoked, all bridge mints will revert, causing a denial of service for inbound bridging.

This is partially mitigated by the `onlyExternalAdmin` modifier for registration, but there is no explicit on‑chain check that the role is actually granted.

**Severity:** Informational

**Location:** {'file': 'LimitedMinterBridge.sol', 'line': 1024, 'code_snippet': '        ILatamStableToken(token).mint(to, mintAmount);'}

**Swc:** SWC-105

**Recommendation:** As with `LimitedMinter`, add:

1) A view helper:
```solidity
function hasMinterRoleOnToken(address token) external view returns (bool) {
    return ILatamStableToken(token).hasRole(ILatamStableToken(token).MINTER_ROLE(), address(this));
}
```

2) Optionally, in `registerToken`, check that `MINTER_ROLE` is granted and revert or emit a dedicated event if not.

3) Ensure operational tooling periodically verifies that `LimitedMinterBridge` retains `MINTER_ROLE` on all registered tokens.

---

### Finding 7

**Contract_Name:** LatamStable

**Title:** Upgradeable token relies on external role management without explicit admin sanity checks

**Description:** The `LatamStable` contract is UUPS‑upgradeable and uses `AccessControlUpgradeable` for roles (`DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `MINTER_ROLE`, `UPGRADER_ROLE`). The `initialize` function assigns these roles to addresses provided as parameters, but there is no on‑chain restriction that these addresses are multisigs or otherwise secure.

If a deployer accidentally passes an EOA or a compromised address as `upgrader`, `minter`, or `defaultAdmin`, the entire token can be upgraded or minted arbitrarily by that address. This is a governance/operational risk rather than a code bug, but given the criticality of an upgradeable stablecoin, it is worth highlighting.

Additionally, there is no explicit function to change the `UPGRADER_ROLE` after initialization except via `grantRole`/`revokeRole` by `DEFAULT_ADMIN_ROLE`, which is correct but requires careful governance.

**Severity:** Informational

**Location:** {'file': 'LatamStable.sol', 'line': 1320, 'code_snippet': '    function initialize(address defaultAdmin, address pauser, address minter, address upgrader, string memory tokenName, string memory tokenSymbol)\n        public initializer\n    {\n        __ERC20_init(tokenName, tokenSymbol);\n        __ERC20Burnable_init();\n        __ERC20Pausable_init();\n        __AccessControl_init();\n        __ERC20Permit_init(tokenName);\n        __UUPSUpgradeable_init();\n\n        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);\n        _grantRole(PAUSER_ROLE, pauser);\n        _grantRole(MINTER_ROLE, minter);\n        _grantRole(UPGRADER_ROLE, upgrader);\n    }'}

**Swc:** SWC-124

**Recommendation:** This is largely a governance concern, but you can:

1) Document clearly in NatSpec and deployment docs that `defaultAdmin`, `pauser`, `minter`, and `upgrader` must be secure multisig or governance contracts.

2) Optionally, add a one‑time `setInitialAdmins` pattern that can only be called once by the deployer and then renounces deployer privileges, to reduce the chance of misconfiguration.

3) Provide a view helper that returns all current role holders (using `AccessControlEnumerableUpgradeable` instead of `AccessControlUpgradeable` if you want enumeration) to aid monitoring.

4) Ensure that upgrade governance includes a timelock and off‑chain review process for new implementations.

---

