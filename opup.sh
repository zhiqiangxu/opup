#!/bin/bash
set -e

trap 'echo "Error occurred in command: $BASH_COMMAND, at line $LINENO"; exit 1' ERR

# dispatch for subcommands if specified
if [ "$#" -ne 0 ]; then
    case $1 in
        blockscout)
            DOCKER_REPO=blockscout-optimism docker compose -f geth.yml up
            ;;
        *)
            echo "unknown subcommand $1"
            exit 1
            ;;
    esac
    return
fi

function download_repo() {
    name=$1
    url=$2
    branch=$3

    if [ -e "$name" ]; then
        read -p "$name already exists, do you want to override? Y/n " answer
        case $answer in
            Y)
                ;;
            n)
                return
                ;;
            *)
                # treat default as Y
                ;;
        esac
    fi
    rm -rf $name
    git clone --branch $branch $url $name
}

function codesize_at_address() {
    addr=$1
    rpc=$2
    cast codesize $addr --rpc-url $rpc
}

function l1_chain_id() {
    cast chain-id --rpc-url $L1_RPC_URL
}

function wait_create2_factory_deployed() {
    while true; do
        sleep 2
        output=$(codesize_at_address 0x4e59b44847b379578588920cA78FbF26c0B4956C $L1_RPC_URL | tr -d '\n')
        if [[ "$output" -ne 0 ]]; then
            echo "create2 factory does exist!"
            return
        else
            echo "create2 factory doesn't exist yet, waiting..."
        fi
    done
}

function ensure_create2_factory_deployed() {
    output=$(codesize_at_address 0x4e59b44847b379578588920cA78FbF26c0B4956C $L1_RPC_URL | tr -d '\n')
    if [[ "$output" -eq 0 ]]; then
        prompt "Next we'll deploy the Create2 factory contract at 0x4e59b44847b379578588920cA78FbF26c0B4956C.
Please fund 0x3fAB184622Dc19b6109349B94811493BF2a45362(the factory deployer) with some ETH.
Press Enter after you funded."
        cast publish --rpc-url $L1_RPC_URL 0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222 
        wait_create2_factory_deployed
    fi
}

function open_with_lineno() {
    f=$1
    vi -c "set number" $f
}

function edit_envrc_and_approve() {
    open_with_lineno .envrc
    direnv allow
    eval "$(direnv export bash)"
}

function prompt() {
    msg=$1
    echo -e "\n$msg"
    read
}

function initialize_op_geth() {
    cd op-geth/
    mkdir datadir
    build/bin/geth init --datadir=datadir genesis.json
    popd
}

function startup_op_services() {
    echo "xxx"
}

function deploy_explorer() {
    git clone https://github.com/blockscout/blockscout.git -b production-optimism
    cd blockscout/docker-compose

    screen -d -m -S blockscout bash -c "$0 blockscout"
}


read -p "Please enter your optimism url: " optimism
read -p "Please enter your optimism branch: " optimismBranch
read -p "Please enter your op-geth url: " opgeth
read -p "Please enter your op-geth branch: " opgethBranch


optimism="https://github.com/ethstorage/optimism"
optimismBranch="op-es"
opgeth="https://github.com/ethstorage/op-geth"
opgethBranch="op-es"


# download repos
download_repo "optimism" $optimism $optimismBranch
download_repo "op-geth" $opgeth $opgethBranch

# build contracts and binaries
pushd optimism
pushd packages/contracts-bedrock/
just build
popd
make op-node op-batcher op-proposer op-challenger
cd op-deployer
just build
popd

pushd op-geth
make geth
popd

# fill out ".envrc": L1_RPC_URL and L1_RPC_KIND
pushd optimism
cp .envrc.example .envrc

prompt "Next we'll fill out the environment variable file ".envrc", finish by quiting the editor.
First, let's fill the L1_RPC_URL and L1_RPC_KIND.
Press Enter to continue..."


edit_envrc_and_approve

# fill out ".envrc": L1_CHAIN_ID and L2_CHAIN_ID
prompt "Next please configure L1_CHAIN_ID and L2_CHAIN_ID, finish by quiting the editor.
Press Enter to continue..."

while true; do
    edit_envrc_and_approve

    # ensure L1_CHAIN_ID is consistent with L1_RPC_URL
    if [ -z "${L1_RPC_URL}" ]; then
        prompt "Please configure L1_RPC_URL.
Press Enter to continue"
        continue
    fi
    if [ -z "${L1_CHAIN_ID}" ]; then
        prompt "Please configure L1_CHAIN_ID.
Press Enter to continue"
        continue
    fi
    rpc_l1_chainid=$(l1_chain_id | tr -d '\n')
    if [[ "$rpc_l1_chainid" -eq $L1_CHAIN_ID ]]; then
        echo "equal $rpc_l1_chainid $L1_CHAIN_ID"
        break
    else
        prompt "chainid of L1_RPC_URL doesn't match L1_CHAIN_ID, reconfigure...
Press Enter to continue..."
    fi
done

# fill out ".envrc": wallets
./packages/contracts-bedrock/scripts/getting-started/wallets.sh

prompt "
Please copy the above, next we'll fill it into .envrc.

Press Enter to continue..."

edit_envrc_and_approve

prompt "Please fund the addresses.
Recommendations for Sepolia are:

\tAdmin — 0.5 Sepolia ETH
\tProposer — 0.2 Sepolia ETH
\tBatcher — 0.1 Sepolia ETH

Press Enter after you funded."

# fill out deploy config
cd packages/contracts-bedrock
./scripts/getting-started/config.sh


prompt "Next please review and configure the deploy config, finish by quiting the editor.

Press Enter to continue..."


open_with_lineno deploy-config/getting-started.json

# ensure that Create2 factory is deployed
ensure_create2_factory_deployed

# deploy the L1 contracts
echo "Now deploy the L1 contracts..."
DEPLOY_CONFIG_PATH=deploy-config/getting-started.json \
forge script scripts/deploy/Deploy.s.sol:Deploy \
    --private-key $GS_ADMIN_PRIVATE_KEY \
    --broadcast --rpc-url $L1_RPC_URL \
    --slow

# generate the L2 config files
echo "Now generate the L2 config files(genesis.json/rollup.json/jwt.txt)..."

CONTRACT_ADDRESSES_PATH=deployments/$L1_CHAIN_ID-deploy.json\
DEPLOY_CONFIG_PATH=deploy-config/getting-started.json \
STATE_DUMP_PATH=l2_allocs.json \
forge script scripts/L2Genesis.s.sol:L2Genesis --sig 'runWithStateDump()' --chain-id $L2_CHAIN_ID

cd ../../op-node/
./bin/op-node genesis l2 --deploy-config ../packages/contracts-bedrock/deploy-config/getting-started.json \
    --l1-deployments ../packages/contracts-bedrock/deployments/11155111-deploy.json \
    --l2-allocs ../packages/contracts-bedrock/l2_allocs.json  \
    --outfile.l2 genesis.json   \
    --outfile.rollup rollup.json   \
    --l1-rpc $L1_RPC_URL

openssl rand -hex 32 > jwt.txt
cp genesis.json ../../op-geth/
cp jwt.txt ../../op-geth/


popd #packages/contracts-bedrock

popd #optimism

# initialize op-geth
echo "Now initialize op-geth..."

initialize_op_geth



echo "Now start up all services..."

startup_op_services
deploy_explorer


prompt "Congratulations, installation finished!
Press Enter to continue..."


