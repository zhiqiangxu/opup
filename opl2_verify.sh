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

echo "Starting verification of $total_contracts L2 predeploy contracts..."
echo ""

# Iterate through each contract and verify
for contract_info in "${L2_CONTRACTS[@]}"; do
    IFS=':' read -r address contract_file contract_name <<< "$contract_info"

    echo "----------------------------------------"
    echo "Verifying: $contract_name"
    echo "Address: $address"
    echo "Contract: $contract_file:$contract_name"
    echo ""

    # Check if contract exists at the address
    code=$(cast code "$address" --rpc-url "$L2_RPC_URL" 2>/dev/null)
    if [ -z "$code" ] || [ "$code" = "0x" ]; then
        echo "⚠ Skipping: No contract code at address $address"
        ((skipped_count++))
        echo ""
        continue
    fi

    # Run forge verify-contract
    if forge verify-contract \
        --rpc-url "$L2_RPC_URL" \
        "$address" \
        "$contract_file:$contract_name" \
        --verifier blockscout \
        --verifier-url "$BLOCKSCOUT_URL/api/" \
        --watch; then
        echo "✓ Successfully verified: $contract_name"
        ((success_count++))
    else
        echo "✗ Failed to verify: $contract_name"
        ((failed_count++))
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
