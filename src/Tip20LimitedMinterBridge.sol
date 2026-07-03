// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITIP20} from "./interfaces/ITIP20.sol";

/**
 * @title Tip20LimitedMinterBridge
 * @notice Tempo-native bridge mint control plane for TIP-20 tokens.
 * @dev Mirrors Ripio's LimitedMinterBridge but uses local config admin roles and
 *      TIP-20 issuer authority instead of ERC-20 token role reads. Operators can
 *      mint with or without TIP-20 memos.
 */
contract Tip20LimitedMinterBridge is AccessControlEnumerable, ReentrancyGuard, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TOKEN_CONFIG_ADMIN_ROLE = keccak256("TOKEN_CONFIG_ADMIN_ROLE");

    struct TokenConfig {
        uint256 dailyMaxMint;
        bool exists;
    }

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(uint256 => uint256)) public mintedPerDay;

    event TokenRegistered(address indexed token, uint256 dailyMaxMint);
    event TokenUnregistered(address indexed token);
    event DailyMintLimitUpdated(address indexed token, uint256 newLimit);
    event Minted(address indexed token, address indexed minter, address indexed to, uint256 amount, bytes32 memo);

    error TokenNotRegistered();
    error InvalidTokenAddress();
    error TokenAlreadyRegistered();
    error MintAmountZero();
    error ExceedsDailyMintLimit();
    error InvalidRecipient();
    error UnexpectedTokenDelivery();
    error ZeroAddress();

    constructor(address defaultAdmin, address minter, address configAdmin) {
        if (defaultAdmin == address(0) || minter == address(0) || configAdmin == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(TOKEN_CONFIG_ADMIN_ROLE, configAdmin);
    }

    modifier tokenExists(address token) {
        if (!tokenConfigs[token].exists) revert TokenNotRegistered();
        _;
    }

    function registerToken(address token, uint256 dailyMaxMint) external onlyRole(TOKEN_CONFIG_ADMIN_ROLE) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (tokenConfigs[token].exists) revert TokenAlreadyRegistered();

        tokenConfigs[token] = TokenConfig({dailyMaxMint: dailyMaxMint, exists: true});

        emit TokenRegistered(token, dailyMaxMint);
    }

    function unregisterToken(address token) external onlyRole(TOKEN_CONFIG_ADMIN_ROLE) tokenExists(token) {
        delete tokenConfigs[token];
        emit TokenUnregistered(token);
    }

    function updateDailyMintLimit(address token, uint256 newLimit)
        external
        onlyRole(TOKEN_CONFIG_ADMIN_ROLE)
        tokenExists(token)
    {
        tokenConfigs[token].dailyMaxMint = newLimit;
        emit DailyMintLimitUpdated(token, newLimit);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function mintTo(address token, address to, uint256 mintAmount)
        external
        onlyRole(MINTER_ROLE)
        tokenExists(token)
        nonReentrant
        whenNotPaused
    {
        _mintTo(token, to, mintAmount, bytes32(0), false);
    }

    function mintToWithMemo(address token, address to, uint256 mintAmount, bytes32 memo)
        external
        onlyRole(MINTER_ROLE)
        tokenExists(token)
        nonReentrant
        whenNotPaused
    {
        _mintTo(token, to, mintAmount, memo, true);
    }

    function mintTo(address token, address to, uint256 mintAmount, bytes32 memo)
        external
        onlyRole(MINTER_ROLE)
        tokenExists(token)
        nonReentrant
        whenNotPaused
    {
        _mintTo(token, to, mintAmount, memo, true);
    }

    function _mintTo(address token, address to, uint256 mintAmount, bytes32 memo, bool useMemo) internal {
        if (mintAmount == 0) revert MintAmountZero();
        if (to == address(0)) revert InvalidRecipient();

        TokenConfig storage config = tokenConfigs[token];
        uint256 currentDay = block.timestamp / 1 days;
        uint256 alreadyMinted = mintedPerDay[token][currentDay];

        if (alreadyMinted + mintAmount > config.dailyMaxMint) {
            revert ExceedsDailyMintLimit();
        }

        mintedPerDay[token][currentDay] = alreadyMinted + mintAmount;

        uint256 balanceBefore = ITIP20(token).balanceOf(to);
        if (useMemo) {
            ITIP20(token).mintWithMemo(to, mintAmount, memo);
        } else {
            ITIP20(token).mint(to, mintAmount);
        }
        uint256 balanceAfter = ITIP20(token).balanceOf(to);

        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != mintAmount) {
            revert UnexpectedTokenDelivery();
        }

        emit Minted(token, msg.sender, to, mintAmount, memo);
    }

    function mintedToday(address token) external view tokenExists(token) returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        return mintedPerDay[token][currentDay];
    }
}
