## bss library
# Contains all commands for `shasta bss`
# This includes all bss actions. Largely intended to vew and update boot parameters.

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function bss {
    case "$1" in
        des*)
            shift
            bss_describe "$@"
            ;;
        li*)
            shift
            bss_list
            ;;
        sh*)
            shift
            bss_describe "$@"
            ;;
        map)
            shift
            bss_map "$@"
            ;;
        update_param)
            shift
            bss_update_param "$@"
            ;;
        *)
            shift
            bss_help
            ;;
    esac
}

function bss_help {
    echo    "USAGE: $0 cfs [action]"
    echo    "DESC: BSS options control what image, and kernel parameters nodes boot with. Direct access via cray commands can be done via 'cray bss'"
    echo    "ACTIONS:"
    echo -e "\tlist : List the nodes and the image they pull"
    echo -e "\tshow [node] : show details about a node's settings"
    echo -e "\tdescribe [node] : same as show"
    echo -e "\tmap [image] [node list] : Change the image to boot node with to the provided"
}

function bss_list {
    cray bss bootparameters list --format json | jq -r '.[] | "\(.hosts) \(.kernel)"' | grep -v ^null | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | sed 's/kernel/rootfs/g'
}

function bss_describe {
    convert2xname "$1"
    NODE="$RETURN"
    cray bss bootscript list --name "$NODE"
}

function bss_map {
    local IMAGE NODES KERNEL INITRD NODE PARAMS
    declare -a NODES
    IMAGE="$1"
    shift
    convert2xname "$@"
    NODES=( $RETURN )
    NODE_STRING=$(echo "$RETURN" | sed 's/ /,/g')
    if [[ -z "$NODES" ]]; then
	die "nodelist not given"
    fi
    KERNEL="s3://boot-images/$IMAGE/kernel"
    INITRD="s3://boot-images/$IMAGE/initrd"
    cray bss bootparameters update --kernel "$KERNEL" --initrd "$INITRD" --hosts "$NODE_STRING"

    IMAGE_RAW=$(rest_api_query "ims/images" | jq ".[] | select(.id == \"$IMAGE\")")

    IMAGE_ETAG=$(echo "$IMAGE_RAW" | jq '.link.etag' | sed 's/"//g')

    for NODE in "${NODES[@]}"; do
        PARAMS=$(cray bss bootparameters list --name $NODE --format json | jq -r '.[].params')
        NEW_PARAMS=$(echo "$PARAMS" | sed "s|s3://boot-images/.*/rootfs|s3://boot-images/$IMAGE/rootfs|g" | sed "s/etag=1392eed2dc1f80cc98a0abd9be363236-315 /etag=$IMAGE_ETAG /g")
        cray bss bootparameters update --params "$NEW_PARAMS" --hosts "$NODE"
        echo "$NODE: mapped"
    done
}

function bss_update_param {
    KEY="$1"
    shift
    VALUE="$1"
    shift
    local NODE UPDATED
    declare -a NODES PARAMS

    if [[ -z "$KEY" || -z "$VALUE" ]]; then
        echo "USAGE: $0 bss update_param <key> <value> <nodelist>"
        return 1
    fi

    convert2xname "$@"
    NODES=( $RETURN )
    for NODE in "$NODES"; do
        PARAMS=( $(cray bss bootparameters list --name $NODE --format json | jq -r '.[].params' | sed 's/ /\n/g') )
        NEW_PARAM_STRING=""
        for PARAM in "${PARAMS[@]}"; do
            if [[ "$PARAM" == $KEY=* ]]; then
                PARAM="${KEY}=$VALUE"
                UPDATED=1
            fi
            if [[ -z "$NEW_PARAM_STRING" ]]; then
                NEW_PARAM_STRING="$PARAM"
            else
                NEW_PARAM_STRING="$NEW_PARAM_STRING $PARAM"
            fi
        done
        if [[ -z "$UPDTED" ]]; then
            NEW_PARAM_STRING="$NEW_PARAM_STRING ${KEY}=$VALUE"
        fi
        cray bss bootparameters update --params "$NEW_PARAM_STRING" --hosts "$NODE"
        echo "$NODE: set $KEY=$VALUE"
    done
}
