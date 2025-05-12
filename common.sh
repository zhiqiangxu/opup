#!/bin/bash


function save_cwd() {
    original_cwd=$(pwd)
}

function recover_cwd() {
    cd $original_cwd
}

function prelude() {
    save_cwd

    # Get the directory of the script
    local script_dir=$(dirname "$(realpath "$0")")
    cd $script_dir
    opup_script_path="$script_dir/opup.sh"
    # working directory is the parent directory
    cd ..
}

function postlude() {
    recover_cwd
}

function start_da_server() {
    pushd da-server
    cat <<EOF | jq . > config.json
{
    "SequencerIP": "127.0.0.1",
    "ListenAddr": "0.0.0.0:8888",
    "StorePath":  "/root/da/data"
}
EOF
    popd
    screen -d -m -S "da-server" bash -c "$opup_script_path da"
}

function start_op_services() {
    screen -d -m -S "op-geth" bash -c "$opup_script_path geth"
    screen -d -m -S "op-node" bash -c "$opup_script_path node"
    screen -d -m -S "op-batcher" bash -c "$opup_script_path batcher"
    screen -d -m -S "op-proposer" bash -c "$opup_script_path proposer"
}

function start_explorer() {
    screen -d -m -S "blockscout" bash -c "$opup_script_path blockscout"
}

function activate_direnv() {
    eval "$(direnv export bash)"
}

function replace_string() {
    local file=$1
    local a=$2
    local b=$3
    local separator="${4:-/}"
    sed_replace "s$separator$a$separator$b$separator" $file
}

function replace_env_value() {
    file=$1
    key=$2
    value=$3
    sed_replace "s#$key=.*#$key=$value#" $file
}

# for compatibility between macOS and linux
function sed_replace() {
    cmd=$1
    file=$2
    if [[ "$(uname)" == "Linux" ]]; then
        sed -i "$cmd" $file
    else
        sed -i '' "$cmd" $file
    fi
}

function replace_env_value_or_insert() {
    file=$1
    key=$2
    value=$3
    sed_replace "s#$key=.*#$key=$value#" $file
    
    if ! grep -q "$key=" $file; then
	    echo "export $key=$value" >> $file
    fi
}

function replace_all() {
    file=$1
    a=$2
    b=$3
    sed_replace "s#$a#$b#g" $file
}

function open_with_lineno() {
    f=$1
    vi -c "set number" $f
}

function config_explorer() {

    echo "Ready to deploy explorer..."
    hostIP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    prompt "Please review the environment variables in "common-frontend.env", finish by quiting the editor.
Press Enter to continue..."
    
    pushd optimism
    activate_direnv
    l2ChainID=$L2_CHAIN_ID
    popd
    pushd blockscout
    replace_env_value docker-compose/envs/common-blockscout.env "CHAIN_ID" $l2ChainID
    replace_env_value docker-compose/envs/common-blockscout.env "NFT_MEDIA_HANDLER_ENABLED" "false"
    replace_string docker-compose/envs/common-blockscout.env "# CHAIN_TYPE=" "CHAIN_TYPE=optimism"
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_API_HOST" $hostIP
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_STATS_API_HOST" "http://$hostIP:8080"
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_APP_HOST" $hostIP
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_ID" $l2ChainID
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_VISUALIZE_API_HOST" "http://$hostIP:8081"
    replace_env_value_or_insert docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_RPC_URL" "http://$hostIP:8545"
    replace_all docker-compose/proxy/default.conf.template "add_header 'Access-Control-Allow-Origin' 'http://localhost' always;" "add_header 'Access-Control-Allow-Origin' '*' always;"
    if [ -n "${ES}" ]; then
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_NAME" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_NAME" "Super world computer"
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_SHORT_NAME" "Super world computer"
    fi
    open_with_lineno docker-compose/envs/common-frontend.env
    popd
}

function save_to_session_history() {
    local session=${STY##*.}
    local cmd=$1
    echo $cmd >> "$session.history"
}