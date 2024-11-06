#!/bin/bash

set -e
trap 'echo "Error occurred in command: $BASH_COMMAND, at line $LINENO"; exit 1' ERR

function quit_session_if_exists() {
    session=$1
    if screen -ls | grep -q "$session"; then
        echo "quiting session '$session'"
        screen -X -S "$session" quit
    fi
}

quit_session_if_exists "op-batcher"
quit_session_if_exists "op-proposer"
quit_session_if_exists "op-node"
quit_session_if_exists "op-geth"
quit_session_if_exists "blockscout"
quit_session_if_exists "da-server"
