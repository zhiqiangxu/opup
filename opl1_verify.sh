#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude


cd optimism/op-deployer
direnv allow
eval "$(direnv export bash)"

# Check if required environment variables are set
if [ -z "$L1_RPC_URL" ]; then
    echo "Error: L1_RPC_URL environment variable is not set"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Warning: ETHERSCAN_API_KEY environment variable is not set"
    echo "Contract verification requires an Etherscan API key"
    exit 1
fi

if [ -z "$L2_CHAIN_ID" ]; then
    echo "Error: L2_CHAIN_ID environment variable is not set"
    exit 1
fi

# Check if deployment state exists
if [ ! -d ".deployer" ]; then
    echo "Error: .deployer directory not found. Please run deployment first."
    exit 1
fi

echo "Verifying L1 contracts for chain ID: $L2_CHAIN_ID"
echo "L1 RPC URL: $L1_RPC_URL"

# Get deployment information and save to temp file
deployment_file=".deployer/l1-deployment-${L2_CHAIN_ID}.json"
echo "Fetching deployment information..."
./bin/op-deployer inspect l1 --workdir .deployer $L2_CHAIN_ID > "$deployment_file"

if [ ! -f "$deployment_file" ]; then
    echo "Error: Failed to fetch deployment information"
    exit 1
fi

echo "Starting contract verification on Etherscan..."
echo "This may take several minutes..."

# Run the verification command
# The verify command will read contract addresses from the deployment file
# and verify each contract on Etherscan
./bin/op-deployer verify \
    --l1-rpc-url "$L1_RPC_URL" \
    --artifacts-locator "file://$(pwd)/../packages/contracts-bedrock/forge-artifacts/" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --input-file "$deployment_file"

verification_status=$?

if [ $verification_status -eq 0 ]; then
    echo "✓ Contract verification completed successfully"
else
    echo "✗ Contract verification failed with status: $verification_status"
fi

postlude
exit $verification_status
