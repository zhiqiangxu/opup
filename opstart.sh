#!/bin/bash

# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude


if [ -n "${ES}" ]; then
    start_da_server
fi
start_op_services
start_explorer

postlude