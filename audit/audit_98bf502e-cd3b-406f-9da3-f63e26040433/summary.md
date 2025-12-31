## Audit Findings Summary (Ordered by Severity → Consensus)

---

### 🔴 MEDIUM SEVERITY

#### Full Consensus (5)
| # | Title | Contract |
|---|-------|----------|
| 1 | Fee collection and burn use two different mechanisms, risking inconsistent behavior with non‑standard tokens | BridgeDeposit |
| 2 | Potential Front-Running of Route Fee Updates | BridgeDeposit |
| 3 | External Admin Check Relies on External Contract's hasRole Implementation | LimitedMinterBridge |
| 4 | No Mechanism to Cancel or Timeout Pending Bridge Operations | BridgeDeposit |
| 5 | Centralization Risk in Bridge Operations | BridgeDeposit |

#### Disputed (2)
| # | Title | Contract |
|---|-------|----------|
| 6 | State updates are not ordered correctly, violating CEI pattern | BridgeDeposit (fix)
| 7 | Incorrect ordering of operations in depositForBridge can lead to reused deposit IDs | BridgeDeposit |

---

### 🟡 LOW SEVERITY

#### Full Consensus (5)
| # | Title | Contract |
|---|-------|----------|
| 1 | Lack of explicit check that BridgeDeposit has MINTER_ROLE on LimitedMinterBridge | BridgeDeposit | (fix)
| 2 | Route configuration does not validate that token is registered in LimitedMinterBridge | BridgeDeposit | (fix)
| 3 | Double Allowance Consumption Without Clear Documentation | BridgeDeposit |
| 4 | Route Configuration Doesn't Validate destChainId is Non-Zero | BridgeDeposit | (fix)
| 5 | Missing zero-address validation in initializer | LatamStable |

#### Partial Consensus (3)
| # | Title | Contract |
|---|-------|----------|
| 6 | Missing Validation for Token Address in depositForBridge | BridgeDeposit |
| 7 | Missing Input Validation in fulfillBridgeMint for sourceTxHash | BridgeDeposit |
| 8 | Missing Storage Gap in Upgradeable Contract | LatamStable |

#### Disputed (1)
| # | Title | Contract |
|---|-------|----------|
| 9 | Fee Accounting Can Become Inconsistent if Token Transfer Fails Silently | BridgeDeposit |

---

### 🟢 INFORMATIONAL SEVERITY

#### Full Consensus (6)
| # | Title | Contract |
|---|-------|----------|
| 1 | Fee accounting does not expose per-route fee configuration or totals in a structured way | BridgeDeposit |
| 2 | Lack of explicit check that LimitedMinter has MINTER_ROLE on token | LimitedMinter |
| 3 | Lack of explicit check that LimitedMinterBridge has MINTER_ROLE on token | LimitedMinterBridge |
| 4 | No Maximum Limit on dailyMaxMint Configuration | LimitedMinter |
| 5 | No Validation of Zero dailyMaxMint in registerToken | LimitedMinterBridge |
| 6 | Centralization of roles poses a significant risk if compromised | All |

#### Partial Consensus (4)
| # | Title | Contract |
|---|-------|----------|
| 7 | Upgradeable token relies on external role management without explicit admin sanity checks | LatamStable |
| 8 | setBridgeRoutes Can Be Called With Empty Array | BridgeDeposit |
| 9 | Permit Function Susceptible to Front-Running | LatamStable |
| 10 | Public functions that are not called internally should be declared external | LatamStable |

#### Disputed (1)
| # | Title | Contract |
|---|-------|----------|
| 11 | Potential Overflow in Daily Minting Check | LimitedMinter |

---

### Summary Totals

| Severity | Full Consensus | Partial | Disputed | **Total** |
|----------|---------------|---------|----------|-----------|
| Medium | 5 | 0 | 2 | **7** |
| Low | 5 | 3 | 1 | **9** |
| Informational | 6 | 4 | 1 | **11** |
| **Total** | **16** | **7** | **4** | **27** |