// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title LimitedMinter
 * @notice A contract that enforces daily minting limits for multiple LatamStable tokens
 * @dev This contract allows admins of LatamStable tokens to register their tokens and set daily minting limits.
 *      Only addresses with MINTER_ROLE can mint tokens, and they cannot exceed the daily limit.
 *      Days are calculated using Unix time (UTC, starting at 00:00 UTC).
 *      The contract includes protections against reentrancy and can be paused in emergencies.
 */

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @notice Interface for interacting with LatamStable tokens
 * @dev Minimal interface required for LimitedMinter to interact with LatamStable tokens
 */
interface ILatamStableToken {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
    function mint(address to, uint256 amount) external;
}

contract LimitedMinter is AccessControlEnumerable, ReentrancyGuard, Pausable {
    /// @notice Role that allows minting through this contract
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Configuration for each registered token
     * @param mintDestination Address where minted tokens will be sent
     * @param dailyMaxMint Maximum amount that can be minted per day
     * @param exists Whether the token is registered
     */
    struct TokenConfig {
        address mintDestination;
        uint256 dailyMaxMint;
        bool exists;
    }

    /// @notice Maps token address to its configuration
    mapping(address => TokenConfig) public tokenConfigs;
    
    /// @notice Maps (token, day) to amount minted on that day
    /// @dev This mapping persists even if a token is unregistered and re-registered
    mapping(address => mapping(uint256 => uint256)) public mintedPerDay;

    /// @notice Emitted when a token is registered
    event TokenRegistered(address indexed token, address indexed destination, uint256 dailyMaxMint);
    /// @notice Emitted when a token is unregistered
    event TokenUnregistered(address indexed token);
    /// @notice Emitted when a token's mint destination is updated
    event MintDestinationUpdated(address indexed token, address indexed newDestination);
    /// @notice Emitted when a token's daily mint limit is updated
    event DailyMintLimitUpdated(address indexed token, uint256 newLimit);
    /// @notice Emitted when tokens are minted
    event Minted(address indexed token, address indexed minter, address indexed destination, uint256 amount);

    /// @notice Custom errors
    error NotExternalAdmin();
    error TokenNotRegistered();
    error InvalidTokenAddress();
    error TokenAlreadyRegistered();
    error MintAmountZero();
    error ExceedsDailyMintLimit();
    error InvalidMintDestination();

    /**
     * @notice Constructor that sets up roles
     * @param defaultAdmin Address to receive the DEFAULT_ADMIN_ROLE
     * @param minter Address to receive the MINTER_ROLE
     */
    constructor(address defaultAdmin, address minter) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Ensures caller is an admin of the external token
     * @param token Address of the token to check admin rights for
     */
    modifier onlyExternalAdmin(address token) {
        if (!ILatamStableToken(token).hasRole(ILatamStableToken(token).DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotExternalAdmin();
        }
        _;
    }

    /**
     * @notice Ensures the token is registered
     * @param token Address of the token to check
     */
    modifier tokenExists(address token) {
        if (!tokenConfigs[token].exists) {
            revert TokenNotRegistered();
        }
        _;
    }

    /**
     * @notice Registers a new token with its daily mint limit
     * @dev Only callable by an admin of the token being registered
     * @param token Address of the token to register
     * @param mintDestination Address where minted tokens will be sent
     * @param dailyMaxMint Maximum amount that can be minted per day
     */
    function registerToken(
        address token,
        address mintDestination,
        uint256 dailyMaxMint
    ) external onlyExternalAdmin(token) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (mintDestination == address(0)) revert InvalidMintDestination();
        if (tokenConfigs[token].exists) revert TokenAlreadyRegistered();
        tokenConfigs[token] = TokenConfig({
            mintDestination: mintDestination,
            dailyMaxMint: dailyMaxMint,
            exists: true
        });
        emit TokenRegistered(token, mintDestination, dailyMaxMint);
    }

    /**
     * @notice Unregisters a token
     * @dev Only callable by an admin of the token being unregistered
     * @param token Address of the token to unregister
     */
    function unregisterToken(address token) external onlyExternalAdmin(token) tokenExists(token) {
        delete tokenConfigs[token];
        emit TokenUnregistered(token);
    }

    /**
     * @notice Updates the daily mint limit for a token
     * @dev Only callable by an admin of the token
     * @param token Address of the token
     * @param newLimit New daily mint limit
     */
    function updateDailyMintLimit(address token, uint256 newLimit)
        external
        onlyExternalAdmin(token)
        tokenExists(token)
    {
        tokenConfigs[token].dailyMaxMint = newLimit;
        emit DailyMintLimitUpdated(token, newLimit);
    }

    /**
     * @notice Updates the mint destination for a token
     * @dev Only callable by an admin of the token
     * @param token Address of the token
     * @param newDestination New address where minted tokens will be sent
     */
    function updateMintDestination(address token, address newDestination)
        external
        onlyExternalAdmin(token)
        tokenExists(token)
    {
        if (newDestination == address(0)) revert InvalidMintDestination();
        tokenConfigs[token].mintDestination = newDestination;
        emit MintDestinationUpdated(token, newDestination);
    }

    /**
     * @notice Pauses all minting operations
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses all minting operations
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Mints tokens respecting the daily limit
     * @dev Only callable by addresses with MINTER_ROLE
     * @param token Address of the token to mint
     * @param mintAmount Amount to mint
     */
    function mint(address token, uint256 mintAmount)
        external
        onlyRole(MINTER_ROLE)
        tokenExists(token)
        nonReentrant
        whenNotPaused
    {
        if (mintAmount == 0) revert MintAmountZero();
        TokenConfig storage config = tokenConfigs[token];
        uint256 currentDay = block.timestamp / 1 days;
        uint256 alreadyMinted = mintedPerDay[token][currentDay];

        if (alreadyMinted + mintAmount > config.dailyMaxMint) revert ExceedsDailyMintLimit();
        mintedPerDay[token][currentDay] = alreadyMinted + mintAmount;

        ILatamStableToken(token).mint(config.mintDestination, mintAmount);

        emit Minted(token, msg.sender, config.mintDestination, mintAmount);
    }

    /**
     * @notice Returns the amount minted today for a token
     * @dev Reverts if the token is not registered
     * @param token Address of the token
     * @return Amount minted today
     */
    function mintedToday(address token) external view tokenExists(token) returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        return mintedPerDay[token][currentDay];
    }
} 