up mode = "":
    ./opup.sh {{mode}}

down:
    ./opdown.sh

nuke: (down)
    rm -rf optimism op-geth blockscout da-server

    