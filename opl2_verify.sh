#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude


cd optimism/packages/contracts-bedrock
direnv allow
eval "$(direnv export bash)"

# Set default L2 RPC URL if not set
L2_RPC_URL=${L2_RPC_URL:-"http://localhost:8545"}

# Set default Blockscout URL if not set
# For local development, blockscout typically runs on port 80
# Users can override this by setting BLOCKSCOUT_URL environment variable
BLOCKSCOUT_URL=${BLOCKSCOUT_URL:-"http://localhost"}

echo "=========================================="
echo "L2 Contract Verification with Blockscout"
echo "=========================================="
echo "L2 RPC URL: $L2_RPC_URL"
echo "Blockscout URL: $BLOCKSCOUT_URL"
echo ""

# Check if forge is available
if ! command -v forge &> /dev/null; then
    echo "Error: forge command not found. Please install Foundry."
    exit 1
fi

# Function to get implementation address from proxy by calling implementation() method
function get_implementation_address() {
    local proxy_addr=$1
    # Call implementation() method (function selector: 0x5c60da1b)
    local impl_addr=$(cast call "$proxy_addr" "implementation()(address)" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    echo "$impl_addr"
}

# Check if a contract is proxied by calling implementation() method
# Returns 0 (true) if proxied, 1 (false) if not proxied
function is_proxied() {
    local address=$1
    # Try to call implementation() method
    local impl_addr=$(cast call "$address" "implementation()(address)" --rpc-url "$L2_RPC_URL" 2>/dev/null)

    # If the call succeeded and returned a non-zero address, it's proxied
    if [ -n "$impl_addr" ] && [ "$impl_addr" != "0x0000000000000000000000000000000000000000" ] && [ "$impl_addr" != "0x" ]; then
        return 0  # Proxied
    fi
    return 1  # Not proxied
}

# Define L2 predeploy contracts with their addresses and contract paths
# Format: "ADDRESS:CONTRACT_FILE:CONTRACT_NAME"
declare -a L2_CONTRACTS=(
    "0x4200000000000000000000000000000000000016:src/L2/L2ToL1MessagePasser.sol:L2ToL1MessagePasser"
    "0x4200000000000000000000000000000000000007:src/L2/L2CrossDomainMessenger.sol:L2CrossDomainMessenger"
    "0x4200000000000000000000000000000000000010:src/L2/L2StandardBridge.sol:L2StandardBridge"
    "0x4200000000000000000000000000000000000014:src/L2/L2ERC721Bridge.sol:L2ERC721Bridge"
    "0x4200000000000000000000000000000000000011:src/L2/SequencerFeeVault.sol:SequencerFeeVault"
    "0x4200000000000000000000000000000000000012:src/universal/OptimismMintableERC20Factory.sol:OptimismMintableERC20Factory"
    "0x4200000000000000000000000000000000000017:src/L2/OptimismMintableERC721Factory.sol:OptimismMintableERC721Factory"
    "0x4200000000000000000000000000000000000015:src/L2/L1Block.sol:L1Block"
    "0x420000000000000000000000000000000000000F:src/L2/GasPriceOracle.sol:GasPriceOracle"
    "0x4200000000000000000000000000000000000018:src/universal/ProxyAdmin.sol:ProxyAdmin"
    "0x4200000000000000000000000000000000000019:src/L2/BaseFeeVault.sol:BaseFeeVault"
    "0x420000000000000000000000000000000000001A:src/L2/L1FeeVault.sol:L1FeeVault"
    "0x4200000000000000000000000000000000000042:src/governance/GovernanceToken.sol:GovernanceToken"
    "0x4200000000000000000000000000000000000020:src/vendor/eas/SchemaRegistry.sol:SchemaRegistry"
    "0x4200000000000000000000000000000000000021:src/vendor/eas/EAS.sol:EAS"
    "0x4200000000000000000000000000000000000800:src/L2/SoulGasToken.sol:SoulGasToken"
)

total_contracts=${#L2_CONTRACTS[@]}
success_count=0
failed_count=0
skipped_count=0

echo "Starting verification of $total_contracts L2 predeploy contracts (proxies + implementations)..."
echo ""

# Iterate through each contract and verify
for contract_info in "${L2_CONTRACTS[@]}"; do
    IFS=':' read -r address contract_file contract_name <<< "$contract_info"

    echo "----------------------------------------"
    echo "Verifying: $contract_name"
    echo "Proxy Address: $address"
    echo "Contract: $contract_file:$contract_name"
    echo ""

    # Check if contract exists at the proxy address
    code=$(cast code "$address" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    if [ -z "$code" ] || [ "$code" = "0x" ]; then
        echo "⚠ Skipping: No contract code at proxy address $address"
        ((skipped_count++))
        echo ""
        continue
    fi

    # Check if this is a proxied contract
    if is_proxied "$address"; then
        # Verify the proxy contract
        echo "Verifying proxy contract at $address..."
        # For proxied contracts, verify as Proxy
        if forge verify-contract \
            --rpc-url "$L2_RPC_URL" \
            "$address" \
            "src/universal/Proxy.sol:Proxy" \
            --verifier blockscout \
            --verifier-url "$BLOCKSCOUT_URL/api/" \
            --compilation-profile default \
            --watch; then
            echo "✓ Successfully verified proxy: $contract_name"
            ((success_count++))
        else
            echo "✗ Failed to verify proxy: $contract_name"
            ((failed_count++))
        fi
        echo ""
        sleep 2

        # Verify the implementation contract
        impl_address=$(get_implementation_address "$address")

        # Check if we got a valid implementation address
        if [ -z "$impl_address" ] || [ "$impl_address" = "0x0000000000000000000000000000000000000000" ]; then
            echo "⚠ Skipping implementation: Could not fetch implementation address for $contract_name"
            ((skipped_count++))
            echo ""
            continue
        fi

        echo "Verifying implementation contract at $impl_address..."

        # Check if implementation exists
        impl_code=$(cast code "$impl_address" --rpc-url "$L2_RPC_URL" 2>/dev/null)
        if [ -z "$impl_code" ] || [ "$impl_code" = "0x" ]; then
            echo "⚠ Skipping implementation: No contract code at address $impl_address"
            ((skipped_count++))
            echo ""
            continue
        fi

        if forge verify-contract \
            --rpc-url "$L2_RPC_URL" \
            "$impl_address" \
            "$contract_file:$contract_name" \
            --verifier blockscout \
            --verifier-url "$BLOCKSCOUT_URL/api/" \
            --compilation-profile default \
            --watch; then
            echo "✓ Successfully verified implementation: $contract_name"
            ((success_count++))
        else
            echo "✗ Failed to verify implementation: $contract_name"
            ((failed_count++))
        fi
    else
        # For non-proxied contracts, verify directly
        if forge verify-contract \
            --rpc-url "$L2_RPC_URL" \
            "$address" \
            "$contract_file:$contract_name" \
            --verifier blockscout \
            --verifier-url "$BLOCKSCOUT_URL/api/" \
            --compilation-profile default \
            --watch; then
            echo "✓ Successfully verified: $contract_name (not proxied)"
            ((success_count++))
        else
            echo "✗ Failed to verify: $contract_name"
            ((failed_count++))
        fi
    fi

    echo ""

    # Add a small delay to avoid rate limiting
    sleep 2
done

echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Total contracts: $total_contracts"
echo "Successfully verified: $success_count"
echo "Failed: $failed_count"
echo "Skipped: $skipped_count"
echo ""

if [ $failed_count -eq 0 ] && [ $success_count -gt 0 ]; then
    echo "✓ All available contracts verified successfully!"
    exit_code=0
elif [ $success_count -gt 0 ]; then
    echo "⚠ Some contracts failed verification"
    exit_code=1
else
    echo "✗ No contracts were verified successfully"
    exit_code=1
fi

postlude
exit $exit_code
