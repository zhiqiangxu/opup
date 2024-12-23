#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude


cd optimism/op-deployer
direnv allow
eval "$(direnv export bash)"
./bin/op-deployer inspect l1 --workdir .deployer $L2_CHAIN_ID

postlude