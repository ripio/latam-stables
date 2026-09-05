#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_rejected() {
    local args=$1
    local output

    if output=$(make -n deploy-latam-stable ARGS="$args" 2>&1); then
        fail "expected '$args' to be rejected, got: $output"
    fi

    [[ "$output" == *"Unsupported or malformed network"* ]] ||
        fail "missing validation error for '$args': $output"
}

assert_rejected "--network sepolai"
assert_rejected "--network ethereum-mainnet"
assert_rejected "--network=sepolia"
assert_rejected "--network"
assert_rejected "--network ethereum --network sepolia"

assert_rpc() {
    local network=$1
    local variable=$2
    local expected_url="https://${network}.example"
    local output

    output=$(make -n "$variable=$expected_url" deploy-latam-stable ARGS="--slow --network $network")
    [[ "$output" == *"--rpc-url $expected_url"* ]] ||
        fail "'$network' did not select its RPC: $output"
    [[ "$output" != *"--rpc-url http://localhost:8545"* ]] ||
        fail "'$network' unexpectedly selected local Anvil: $output"
}

assert_rpc ethereum ETHEREUM_RPC_URL
assert_rpc sepolia SEPOLIA_RPC_URL
assert_rpc worldchain-sepolia WORLDCHAIN_SEPOLIA_RPC_URL
assert_rpc worldchain WORLDCHAIN_RPC_URL
assert_rpc forked-ethereum FORKED_ETHEREUM_RPC_URL
assert_rpc zkLatestnet LATESTNET_ZK_RPC_URL
assert_rpc base BASE_RPC_URL

local_output=$(make -n deploy-latam-stable)
[[ "$local_output" == *"--rpc-url http://localhost:8545"* ]] ||
    fail "no-network invocation no longer selects local Anvil: $local_output"

printf 'Makefile network selection tests passed\n'
