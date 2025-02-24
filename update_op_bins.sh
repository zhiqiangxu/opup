# Get the directory of the script
script_dir=$(dirname "$(realpath "$0")")
source "$script_dir/common.sh"
prelude


pushd optimism && make op-node op-batcher op-proposer op-challenger cannon op-program && popd
pushd op-geth && make geth && popd

postlude