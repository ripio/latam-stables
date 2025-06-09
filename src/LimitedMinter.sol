// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

interface ILatamStableToken {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
    function mint(address to, uint256 amount) external;
}

contract LimitedMinter is AccessControlEnumerable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct TokenConfig {
        address mintDestination;
        uint256 dailyMaxMint;
        uint256 lastMintDay;
        uint256 totalMintedToday;
        bool exists;
    }

    // token address => config
    mapping(address => TokenConfig) public tokenConfigs;

    event TokenRegistered(address indexed token, address indexed destination, uint256 dailyMaxMint);
    event TokenUnregistered(address indexed token);
    event MintDestinationUpdated(address indexed token, address indexed newDestination);
    event DailyMintLimitUpdated(address indexed token, uint256 newLimit);
    event Minted(address indexed token, address indexed minter, address indexed destination, uint256 amount);

    constructor(address defaultAdmin, address minter) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    modifier onlyExternalAdmin(address token) {
        require(
            ILatamStableToken(token).hasRole(ILatamStableToken(token).DEFAULT_ADMIN_ROLE(), msg.sender),
            "Caller is not an admin of the external token"
        );
        _;
    }

    modifier tokenExists(address token) {
        require(tokenConfigs[token].exists, "Token not registered");
        _;
    }

    function registerToken(
        address token,
        address mintDestination,
        uint256 dailyMaxMint
    ) external onlyExternalAdmin(token) {
        require(token != address(0), "Invalid token address");
        require(!tokenConfigs[token].exists, "Token already registered");
        tokenConfigs[token] = TokenConfig({
            mintDestination: mintDestination,
            dailyMaxMint: dailyMaxMint,
            lastMintDay: 0,
            totalMintedToday: 0,
            exists: true
        });
        emit TokenRegistered(token, mintDestination, dailyMaxMint);
    }

    function unregisterToken(address token) external onlyExternalAdmin(token) tokenExists(token) {
        delete tokenConfigs[token];
        emit TokenUnregistered(token);
    }

    function updateDailyMintLimit(address token, uint256 newLimit)
        external
        onlyExternalAdmin(token)
        tokenExists(token)
    {
        tokenConfigs[token].dailyMaxMint = newLimit;
        emit DailyMintLimitUpdated(token, newLimit);
    }

    function updateMintDestination(address token, address newDestination)
        external
        onlyExternalAdmin(token)
        tokenExists(token)
    {
        tokenConfigs[token].mintDestination = newDestination;
        emit MintDestinationUpdated(token, newDestination);
    }

    function mint(address token, uint256 mintAmount)
        external
        onlyRole(MINTER_ROLE)
        tokenExists(token)
    {
        require(mintAmount > 0, "Mint amount must be greater than zero");
        TokenConfig storage config = tokenConfigs[token];
        uint256 currentDay = block.timestamp / 1 days;

        // Reset daily counter if new day
        if (config.lastMintDay != currentDay) {
            config.lastMintDay = currentDay;
            config.totalMintedToday = 0;
        }

        require(
            config.totalMintedToday + mintAmount <= config.dailyMaxMint,
            "Exceeds daily mint limit"
        );

        config.totalMintedToday += mintAmount;
        ILatamStableToken(token).mint(config.mintDestination, mintAmount);
        emit Minted(token, msg.sender, config.mintDestination, mintAmount);
    }

    // Optional: view function to get current minted amount for a token today
    function mintedToday(address token) external view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        uint256 currentDay = block.timestamp / 1 days;
        if (config.lastMintDay != currentDay) {
            return 0;
        }
        return config.totalMintedToday;
    }
} 