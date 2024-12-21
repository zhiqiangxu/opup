#!/bin/bash

function save_cwd() {
    original_cwd=$(pwd)
}

function recover_cwd() {
    cd $original_cwd
}

save_cwd

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
cd $script_dir
# working directory is the parent directory
cd ..

rm -rf optimism op-geth blockscout da-server es-op-batchinbox izar-contracts storage-contracts-v1

recover_cwd