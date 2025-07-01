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
        # if the 4th parameter is set, do not export
        if [ -n "$4" ]; then
            echo "$key=$value" >> $file
        else
            echo "export $key=$value" >> $file
        fi
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
    replace_env_value_or_insert docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_RPC_URL" "http://$hostIP:8545" 1
    # FYI, these 3 envs are necessary to show L1 fee: https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#rollup-chain
    replace_env_value_or_insert docker-compose/envs/common-frontend.env "NEXT_PUBLIC_ROLLUP_TYPE" "'optimistic'" 1
    # TODO set real value for NEXT_PUBLIC_ROLLUP_L2_WITHDRAWAL_URL
    replace_env_value_or_insert docker-compose/envs/common-frontend.env "NEXT_PUBLIC_ROLLUP_L2_WITHDRAWAL_URL" "https://example.com" 1
    replace_env_value_or_insert docker-compose/envs/common-frontend.env "NEXT_PUBLIC_ROLLUP_L1_BASE_URL" "https://sepolia.etherscan.io/" 1
    replace_all docker-compose/proxy/default.conf.template "add_header 'Access-Control-Allow-Origin' 'http://localhost' always;" "add_header 'Access-Control-Allow-Origin' '*' always;"
    if [ -n "${ES}" ]; then
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_NAME" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_NAME" "Super world computer"
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_SHORT_NAME" "Super world computer"
    fi
    open_with_lineno docker-compose/envs/common-frontend.env

    # if 8081(kurtosis uses this port) is already in use, switch to 8088 instead
    # TODO make it more clever maybe
    if netstat -tuln | grep ":8081"; then
        replace_all docker-compose/envs/common-frontend.env 8081 8088
        replace_all docker-compose/proxy/default.conf.template 8081 8088
        replace_all docker-compose/proxy/microservices.conf.template 8081 8088
        replace_all docker-compose/services/nginx.yml 8081 8088
    fi
    popd
}

function save_to_session_history() {
    local session=${STY##*.}
    echo "$@" >> "$session.history"
}

function remote_signer_flags() {
    endpoint=$1
    address=$2
    tlsCa=$3
    tlsCert=$4
    tlsKey=$5
    shift 5
    local headers=""
    for arg in "$@"; do
        headers+="--signer.header $arg "
    done
    echo "--signer.endpoint $endpoint --signer.address $address --signer.tls.ca $tlsCa --signer.tls.cert $tlsCert --signer.tls.key $tlsKey $headers --signer.tls.enabled"
}

function admin_address() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "$GS_ADMIN_ADDRESS"
    else
        jq -r '.admin.address' $REMOTE_SIGNERS_JSON
    fi
}

function batcher_pk_flags() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "--private-key=$GS_BATCHER_PRIVATE_KEY"
    else
        endpoint=$(jq -r '.batcher.endpoint' $REMOTE_SIGNERS_JSON)
        address=$(jq -r '.batcher.address' $REMOTE_SIGNERS_JSON)
        tlsCa=$(jq -r '.batcher.tlsca' $REMOTE_SIGNERS_JSON)
        tlsCert=$(jq -r '.batcher.tlscert' $REMOTE_SIGNERS_JSON)
        tlsKey=$(jq -r '.batcher.tlskey' $REMOTE_SIGNERS_JSON)
        headers=$(jq -r '.batcher.headers // [] | @tsv' $REMOTE_SIGNERS_JSON)
        remote_signer_flags $endpoint $address $tlsCa $tlsCert $tlsKey ${headers[@]}
    fi
}

function proposer_pk_flags() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "--private-key=$GS_PROPOSER_PRIVATE_KEY"
    else
        endpoint=$(jq -r '.proposer.endpoint' $REMOTE_SIGNERS_JSON)
        address=$(jq -r '.proposer.address' $REMOTE_SIGNERS_JSON)
        tlsCa=$(jq -r '.proposer.tlsca' $REMOTE_SIGNERS_JSON)
        tlsCert=$(jq -r '.proposer.tlscert' $REMOTE_SIGNERS_JSON)
        tlsKey=$(jq -r '.proposer.tls.key' $REMOTE_SIGNERS_JSON)
        headers=$(jq -r '.proposer.headers // [] | @tsv' $REMOTE_SIGNERS_JSON)
        remote_signer_flags $endpoint $address $tlsCa $tlsCert $tlsKey ${headers[@]}
    fi
}

function challenger_pk_flags() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "--private-key=$GS_CHALLENGER_PRIVATE_KEY"
    else
        endpoint=$(jq -r '.challenger.endpoint' $REMOTE_SIGNERS_JSON)
        address=$(jq -r '.challenger.address' $REMOTE_SIGNERS_JSON)
        tlsCa=$(jq -r '.challenger.tlsca' $REMOTE_SIGNERS_JSON)
        tlsCert=$(jq -r '.challenger.tlscert' $REMOTE_SIGNERS_JSON)
        tlsKey=$(jq -r '.challenger.tlskey' $REMOTE_SIGNERS_JSON)
        headers=$(jq -r '.challenger.headers // [] | @tsv' $REMOTE_SIGNERS_JSON)
        remote_signer_flags $endpoint $address $tlsCa $tlsCert $tlsKey ${headers[@]}
    fi
}

function batcher_address() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "$GS_BATCHER_ADDRESS"
    else
        jq -r '.batcher.address' $REMOTE_SIGNERS_JSON
    fi
}

function proposer_address() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "$GS_PROPOSER_ADDRESS"
    else
        jq -r '.proposer.address' $REMOTE_SIGNERS_JSON
    fi
}

function challenger_address() {
    if [ -z "$REMOTE_SIGNERS_JSON" ]; then
        echo "$GS_CHALLENGER_ADDRESS"
    else
        jq -r '.challenger.address' $REMOTE_SIGNERS_JSON
    fi
}