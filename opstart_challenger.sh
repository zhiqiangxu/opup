#!/bin/bash

# ******* important: this script assumes that files under op-deployer/.deployer are available **********


# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude

# ensure binaries/prestate are generated
pushd optimism/cannon
make cannon
cd ../op-program
make op-program
make reproducible-prestate
cd ../op-deployer
just build
popd

# invoke op-challenger after everything is ready
screen -d -m -S "op-challenger" bash -c "$opup_script_path challenger"

postlude