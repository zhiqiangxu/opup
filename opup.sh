#!/bin/bash


function prompt() {
    msg=$1
    echo -e "\n$msg"
    read
}

function activate_direnv() {
    eval "$(direnv export bash)"
}

# dispatch for subcommands if specified
if [ "$#" -ne 0 ]; then
    continue=0
    case $1 in
        da)
            cd da-server
            go run main.go da start --config config.json
            prompt "Press Enter to quit..."
            ;;
        geth)
            pushd optimism
            activate_direnv
            l2ChainID=$L2_CHAIN_ID
            popd
            cd op-geth
            ./build/bin/geth --datadir ./datadir   --http   --http.corsdomain="*"   --http.vhosts="*"   --http.addr=0.0.0.0   \
                             --http.api=web3,debug,eth,txpool,net,engine,miner   --ws   --ws.addr=0.0.0.0   --ws.port=8546   --ws.origins="*" \
                             --ws.api=debug,eth,txpool,net,engine,miner   --syncmode=full   --gcmode=archive   --nodiscover   --maxpeers=0  \
                             --networkid=$l2ChainID --authrpc.vhosts="*"   --authrpc.addr=0.0.0.0   --authrpc.port=8551   \
                             --authrpc.jwtsecret=./jwt.txt  --rollup.disabletxpoolgossip=true  2>&1 | tee -a geth.log -i
            prompt "Press Enter to quit..."
            ;;
        node)
            cd optimism/op-node
            activate_direnv
            dacParam=""
            if [ -n "${ES}" ]; then
                dacParam="--dac.urls=http://localhost:8888"
            fi
            ./bin/op-node   --l2=http://localhost:8551   --l2.jwt-secret=./jwt.txt   --sequencer.enabled  \
                            --sequencer.l1-confs=5   --verifier.l1-confs=4   --rollup.config=./rollup.json \
                            --rpc.addr=0.0.0.0   --rpc.port=8547  --p2p.listen.ip=0.0.0.0 --p2p.listen.tcp=9003\
                            --p2p.listen.udp=9003   --rpc.enable-admin   --p2p.sequencer.key=$GS_SEQUENCER_PRIVATE_KEY\
                            --l1=$L1_RPC_URL   --l1.rpckind=$L1_RPC_KIND --l1.beacon=$L1_BEACON_URL \
                            $dacParam --l1.beacon-archiver=$L1_BEACON_ARCHIVER_URL 2>&1 | tee -a node.log -i
            prompt "Press Enter to quit..."
            ;;
        batcher)
            cd optimism/op-batcher
            activate_direnv
            ./bin/op-batcher   --l2-eth-rpc=http://localhost:8545   --rollup-rpc=http://localhost:8547   --poll-interval=1s   \
                               --sub-safety-margin=20   --num-confirmations=1   --safe-abort-nonce-too-low-count=3   --resubmission-timeout=30s\
                               --rpc.addr=0.0.0.0   --rpc.port=8548   --rpc.enable-admin      --l1-eth-rpc=$L1_RPC_URL   \
                               --private-key=$GS_BATCHER_PRIVATE_KEY --data-availability-type blobs \
                               --batch-type=1 --max-channel-duration=3600 2>&1 | tee -a batcher.log -i
            prompt "Press Enter to quit..."
            ;;
        proposer)
            pushd optimism/op-deployer
            activate_direnv
            gameFactoryAddr=$(./bin/op-deployer inspect l1 --workdir .deployer/ $L2_CHAIN_ID | jq -r '.opChainDeployment.disputeGameFactoryProxyAddress')
            popd
            cd optimism/op-proposer
            activate_direnv
            ./bin/op-proposer --poll-interval=12s --rpc.port=8560 --rollup-rpc=http://localhost:8547 \
                              --game-factory-address=$gameFactoryAddr \
                              --proposal-interval 12h --game-type 1\
                              --private-key=$GS_PROPOSER_PRIVATE_KEY --l1-eth-rpc=$L1_RPC_URL 2>&1 | tee -a proposer.log -i
            prompt "Press Enter to quit..."
            ;;
        blockscout)
            cd blockscout/docker-compose
            DOCKER_REPO=blockscout-optimism docker compose -f geth.yml up
            prompt "Press Enter to quit..."
            ;;
        --es)
            export ES=true
            continue=1
            ;;
        --start_es)
            export ES=true
            start=true
            continue=1
            ;;
        *)
            echo "unknown subcommand $1"
            exit 1
            ;;
    esac
    if [ $continue -eq 0 ]; then
        exit 0
    fi
fi

function set_error_on() {
    set -e
    trap 'echo "Error occurred in command: $BASH_COMMAND, at line $LINENO"; exit 1' ERR
}

set_error_on

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
    if [ -z $branch ]; then
        git clone $url $name
    else
        git clone --branch $branch $url $name
    fi
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

function initialize_op_geth() {
    pushd op-geth/
    rm -rf datadir
    mkdir datadir
    build/bin/geth init --datadir=datadir  --state.scheme hash genesis.json
    popd
}

function startup_op_services() {
    screen -d -m -S "op-geth" bash -c "$0 geth"
    screen -d -m -S "op-node" bash -c "$0 node"
    screen -d -m -S "op-batcher" bash -c "$0 batcher"
    screen -d -m -S "op-proposer" bash -c "$0 proposer"
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
    screen -d -m -S "da-server" bash -c "$0 da"
}



function deploy_explorer() {

    echo "Ready to deploy explorer..."
    hostIP=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    prompt "Please review the environment variables in "common-frontend.env", finish by quiting the editor.
Press Enter to continue..."
    
    pushd blockscout
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_API_HOST" $hostIP
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_STATS_API_HOST" "http://$hostIP:8080"
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_APP_HOST" $hostIP
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_ID" $L2_CHAIN_ID
    replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_VISUALIZE_API_HOST" "http://$hostIP:8081"
    if [ -n "${ES}" ]; then
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_NAME" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL" QKC
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_NAME" "Super world computer"
        replace_env_value docker-compose/envs/common-frontend.env "NEXT_PUBLIC_NETWORK_SHORT_NAME" "Super world computer"
    fi
    open_with_lineno docker-compose/envs/common-frontend.env
    popd
    screen -d -m -S "blockscout" bash -c "$0 blockscout"
}

function quote_string() {
    local input="$1"
    # Escape double quotes and backslashes
    local escaped="${input//\\/\\\\}"  # Escape backslashes
    escaped="${escaped//\"/\\\"}"       # Escape double quotes
    echo "\"$escaped\""
}

function replace_toml_value() {
    file=$1
    key=$2
    value=$3
    sed -i "s#$key = .*#$key = $value#" $file
}

function replace_env_value() {
    file=$1
    key=$2
    value=$3
    sed -i "s#$key=.*#$key=$value#" $file
}

function replace_env_value_or_insert() {
    file=$1
    key=$2
    value=$3
    sed -i "s#$key=.*#$key=$value#" $file
    
    if ! grep -q "$key=" $file; then
	    echo "export $key=$value" >> $file
    fi
}

if [ -z $start ]; then
    if [ -n "${ES}" ]; then
        optimism="https://github.com/ethstorage/optimism"
        optimismBranch="op-es"
        opgeth="https://github.com/ethstorage/op-geth"
        opgethBranch="op-es"
    else
        read -p "Please enter your optimism url: " optimism
        read -p "Please enter your optimism branch: " optimismBranch
        read -p "Please enter your op-geth url: " opgeth
        read -p "Please enter your op-geth branch: " opgethBranch
    fi


    # download repos
    download_repo "optimism" $optimism $optimismBranch
    download_repo "op-geth" $opgeth $opgethBranch
    download_repo "da-server" https://github.com/ethstorage/da-server
    download_repo "blockscout" https://github.com/blockscout/blockscout production-optimism

    # build contracts and binaries
    pushd optimism

    pushd packages/contracts-bedrock/
    forge clean
    just build
    popd
    make op-node op-batcher op-proposer op-challenger
    cd op-deployer
    just build
    popd

    pushd op-geth
    make geth
    popd

    # fill out ".envrc": L1_RPC_URL/L1_RPC_KIND/L1_BEACON_URL/L1_BEACON_ARCHIVER_URL/L1_CHAIN_ID/L2_CHAIN_ID
    pushd optimism
    if [ ! -e .envrc ]; then
        cp .envrc.example .envrc
    fi

    if [ -n "${ES}" ]; then
        replace_env_value .envrc L1_RPC_URL "http://88.99.30.186:8545"
        replace_env_value .envrc L1_RPC_KIND standard
        replace_env_value_or_insert .envrc L1_BEACON_URL "http://88.99.30.186:3500"
        replace_env_value_or_insert .envrc L1_BEACON_ARCHIVER_URL "http://65.108.236.27:9645"
    fi
    prompt "Next we'll fill out the environment variable file ".envrc", finish by quiting the editor.
First, let's fill the L1_RPC_URL/L1_RPC_KIND/L1_BEACON_URL/L1_BEACON_ARCHIVER_URL/L1_CHAIN_ID/L2_CHAIN_ID.
Press Enter to continue..."

    while true; do
        edit_envrc_and_approve

        # ensure L1_BEACON_URL is set
        if [ -z "${L1_BEACON_URL}" ]; then
            prompt "Please configure L1_BEACON_URL.
Press Enter to continue"
            continue
        fi
        # ensure L1_BEACON_ARCHIVER_URL is set
        if [ -z "${L1_BEACON_ARCHIVER_URL}" ]; then
            prompt "Please configure L1_BEACON_ARCHIVER_URL.
Press Enter to continue"
            continue
        fi
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

    # fill out op-deployer intent
    forgeArtifacts="$(pwd)/packages/contracts-bedrock/forge-artifacts/"
    pushd op-deployer

    if [ -e ".deployer/intent.toml" ]; then
        read -p "op-deployer intent config already exists, do you want to override? Y/n " answer
        if [ -z "$answer" ]; then
            answer="Y"
        fi
    else
        answer="Y"
    fi

    if [ "$answer" = "Y" ]; then
        ./bin/op-deployer init --l1-chain-id $L1_CHAIN_ID --l2-chain-ids $L2_CHAIN_ID --workdir .deployer

        replace_toml_value .deployer/intent.toml l1ChainID $L1_CHAIN_ID
        replace_toml_value .deployer/intent.toml l1ContractsLocator  $(quote_string "file://$forgeArtifacts")
        replace_toml_value .deployer/intent.toml l2ContractsLocator $(quote_string "file://$forgeArtifacts")
        replace_toml_value .deployer/intent.toml proxyAdminOwner $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml protocolVersionsOwner $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml guardian $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml baseFeeVaultRecipient $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml l1FeeVaultRecipient $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml sequencerFeeVaultRecipient $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml l1ProxyAdminOwner $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml l2ProxyAdminOwner $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml systemConfigOwner $(quote_string $GS_ADMIN_ADDRESS)
        replace_toml_value .deployer/intent.toml unsafeBlockSigner $(quote_string $GS_SEQUENCER_ADDRESS)
        replace_toml_value .deployer/intent.toml batcher $(quote_string $GS_BATCHER_ADDRESS)
        replace_toml_value .deployer/intent.toml proposer $(quote_string $GS_PROPOSER_ADDRESS)
        replace_toml_value .deployer/intent.toml challenger $(quote_string $GS_CHALLENGER_ADDRESS)

        if [ -n "${ES}" ]; then
            if ! grep -q "\[globalDeployOverrides\]" .deployer/intent.toml; then
                echo "
[globalDeployOverrides]
  useInboxContract = true
  useSoulGasToken = true
  isSoulBackedByNative = true
  useCustomGasToken = true
  customGasTokenAddress = "0xe6ABD81D16a20606a661D4e075cdE5734AB62519"
  batchInboxAddress = "0x27504265a9bc4330e3fe82061a60cd8b6369b4dc"
  l2GenesisBlobTimeOffset = "0x0"
  sequencerWindowSize = 7200" >> .deployer/intent.toml
            fi
        fi
    fi


    prompt "Next please review and configure the op-deployer intent config, finish by quiting the editor.

Press Enter to continue..."


    open_with_lineno .deployer/intent.toml

    # ensure that Create2 factory is deployed
    ensure_create2_factory_deployed

    prompt "Now we're ready to apply op-deployer intent config.
Press Enter to continue..."
    ./bin/op-deployer apply --workdir .deployer --l1-rpc-url $L1_RPC_URL --private-key $GS_ADMIN_PRIVATE_KEY

    # generate the L2 config files(genesis.json/rollup.json/jwt.txt)
    prompt "Now generate the L2 config files(genesis.json/rollup.json/jwt.txt)...
Press Enter to continue..."

    ./bin/op-deployer inspect genesis --workdir .deployer $L2_CHAIN_ID | tee ../op-node/genesis.json ../../op-geth/genesis.json > /dev/null
    ./bin/op-deployer inspect rollup --workdir .deployer $L2_CHAIN_ID | tee ../op-node/rollup.json ../../op-geth/rollup.json > /dev/null

    openssl rand -hex 32 | tee ../op-node/jwt.txt ../../op-geth/jwt.txt > /dev/null

    popd #op-deployer

    popd #optimism

    # initialize op-geth
    prompt "Now initialize op-geth...
Press Enter to continue..."

    initialize_op_geth



    prompt "Now start up all services...
Press Enter to continue..."
fi


# Now start all services
if [ -n "${ES}" ]; then
    start_da_server
fi
startup_op_services
deploy_explorer



prompt "Congratulations, installation finished!
Press Enter to continue..."


