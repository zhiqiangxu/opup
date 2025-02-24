up mode = "":
    ./opup.sh {{mode}}

down:
    ./opdown.sh

nuke: (down)
    ./opnuke.sh

start:
    ./opstart.sh    

l1:
    ./opl1.sh

update_op_bins:
    ./update_op_bins.sh
