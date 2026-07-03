// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ITIP20} from "../src/interfaces/ITIP20.sol";
import {ITIP20Factory} from "../src/interfaces/ITIP20Factory.sol";

contract DeployTip20LatamStable is Script {
    address internal constant TIP20_FACTORY = 0x20Fc000000000000000000000000000000000000;

    struct Config {
        string name;
        string symbol;
        string currency;
        address quoteToken;
        address admin;
        bytes32 salt;
        string logoURI;
    }

    error EmptyName();
    error EmptySymbol();
    error EmptyCurrency();
    error LogoURITooLong();
    error QuoteTokenNotTIP20(address quoteToken);
    error Tip20AlreadyDeployed(address token);
    error UnexpectedTokenAddress(address expected, address actual);
    error UsdTokenRequiresUsdQuoteToken(address quoteToken, string quoteCurrency);
    error ZeroAdmin();

    function run(address wallet) public returns (address) {
        Config memory config = _loadConfig();
        ITIP20Factory factory = ITIP20Factory(TIP20_FACTORY);
        address expectedToken = factory.getTokenAddress(wallet, config.salt);

        _validate(factory, config, expectedToken);
        _logPreDeploy(factory, config, wallet, expectedToken);

        vm.startBroadcast(wallet);

        address token = factory.createToken(
            config.name,
            config.symbol,
            config.currency,
            ITIP20(config.quoteToken),
            config.admin,
            config.salt,
            config.logoURI
        );

        vm.stopBroadcast();

        if (token != expectedToken) revert UnexpectedTokenAddress(expectedToken, token);

        _logPostDeploy(config, wallet, token);
        return token;
    }

    function _loadConfig() internal view returns (Config memory config) {
        config = Config({
            name: vm.envString("TOKEN_NAME"),
            symbol: vm.envString("TOKEN_SYMBOL"),
            currency: vm.envString("TOKEN_CURRENCY"),
            quoteToken: vm.envAddress("QUOTE_TOKEN"),
            admin: vm.envAddress("TIP20_ADMIN"),
            salt: vm.envBytes32("TIP20_SALT"),
            logoURI: vm.envOr("TOKEN_LOGO_URI", string(""))
        });
    }

    function _validate(ITIP20Factory factory, Config memory config, address expectedToken) internal view {
        if (bytes(config.name).length == 0) revert EmptyName();
        if (bytes(config.symbol).length == 0) revert EmptySymbol();
        if (bytes(config.currency).length == 0) revert EmptyCurrency();
        if (bytes(config.logoURI).length > 256) revert LogoURITooLong();
        if (config.admin == address(0)) revert ZeroAdmin();
        if (!factory.isTIP20(config.quoteToken)) revert QuoteTokenNotTIP20(config.quoteToken);
        if (factory.isTIP20(expectedToken)) revert Tip20AlreadyDeployed(expectedToken);

        string memory quoteCurrency = ITIP20(config.quoteToken).currency();
        if (_isUsd(config.currency) && !_isUsd(quoteCurrency)) {
            revert UsdTokenRequiresUsdQuoteToken(config.quoteToken, quoteCurrency);
        }
    }

    function _isUsd(string memory currency) internal pure returns (bool) {
        return keccak256(bytes(currency)) == keccak256(bytes("USD"));
    }

    function _logPreDeploy(ITIP20Factory factory, Config memory config, address deployer, address expectedToken)
        internal
        view
    {
        console2.log("--------------------------------");
        console2.log("Creating Tempo TIP-20 token:");
        console2.log("TIP-20 Factory:", TIP20_FACTORY);
        console2.log("Deployer:", deployer);
        console2.log("Expected Token:", expectedToken);
        console2.log("Expected Token Already Deployed:", factory.isTIP20(expectedToken));
        console2.log("Admin:", config.admin);
        console2.log("Quote Token:", config.quoteToken);
        console2.log("Quote Token Is TIP-20:", factory.isTIP20(config.quoteToken));
        console2.log("Quote Token Currency:", ITIP20(config.quoteToken).currency());
        console2.log("Token Name:", config.name);
        console2.log("Token Symbol:", config.symbol);
        console2.log("Token Currency:", config.currency);
        console2.log("Token Logo URI:", config.logoURI);
        console2.logBytes32(config.salt);
        console2.log("--------------------------------");
    }

    function _logPostDeploy(Config memory config, address deployer, address token) internal pure {
        console2.log("--------------------------------");
        console2.log("Tempo TIP-20 token created at:", token);
        console2.log("Deployer:", deployer);
        console2.log("Admin:", config.admin);
        console2.log("Quote Token:", config.quoteToken);
        console2.log("Token Name:", config.name);
        console2.log("Token Symbol:", config.symbol);
        console2.log("Token Currency:", config.currency);
        console2.log("Token Logo URI:", config.logoURI);
        console2.log("Next steps: deploy Tip20LimitedMinter and grant ISSUER_ROLE if capped issuance is desired");
        console2.log("--------------------------------");
    }
}
