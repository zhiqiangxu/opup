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

function save_to_session_history() {
    local session=${STY##*.}
    local cmd=$1
    echo $cmd >> "$session.history"
}