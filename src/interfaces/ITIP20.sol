// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ITIP20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function transferWithMemo(address to, uint256 amount, bytes32 memo) external;
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external returns (bool);
    function mint(address to, uint256 amount) external;
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external;
    function burn(uint256 amount) external;
    function burnWithMemo(uint256 amount, bytes32 memo) external;
    function burnBlocked(address from, uint256 amount) external;

    function quoteToken() external view returns (ITIP20);
    function nextQuoteToken() external view returns (ITIP20);
    function currency() external view returns (string memory);
    function logoURI() external view returns (string memory);
    function transferPolicyId() external view returns (uint64);
    function paused() external view returns (bool);
    function supplyCap() external view returns (uint256);

    function ISSUER_ROLE() external view returns (bytes32);
    function PAUSE_ROLE() external view returns (bytes32);
    function UNPAUSE_ROLE() external view returns (bytes32);
    function BURN_BLOCKED_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role) external;
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

    function pause() external;
    function unpause() external;
    function changeTransferPolicyId(uint64 newPolicyId) external;
    function setNextQuoteToken(ITIP20 newQuoteToken) external;
    function completeQuoteTokenUpdate() external;
    function setSupplyCap(uint256 newSupplyCap) external;
    function setLogoURI(string calldata newLogoURI) external;
}
