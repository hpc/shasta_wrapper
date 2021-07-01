
function node {
    case "$1" in
        boot)
            shift
            node_boot boot "$@"
            ;;
        con*)
            shift
            node_config "$@"
            ;;
        li*)
            shift
            node_list "$@"
            ;;
        des*)
            shift
            node_describe "$@"
            ;;
        reboot)
            shift
            node_boot reboot "$@"
            ;;
        sho*)
            shift
            node_describe "$@"
            ;;
        shutdown)
            shift
            node_boot shutdown "$@"
            ;;
        unconf*)
            shift
            cfs_unconfigured "$@"
            ;;
        *)
            node_help
            ;;
    esac    
}

function node_help {
    echo    "USAGE: $0 node [action]"
    echo    "DESC: shows the node groups information and what configurations, bos sessiontemplates, and images are used for each(details)"
    echo    "ACTIONS:"
    echo -e "\tboot [nodes space seperated] : Boots all nodes that are not booted into the given group's default bos template."
    echo -e "\tconfig [nodes space seperated] : Configures all nodes that are not booted with the given group's default cfs config."
    echo -e "\tdescribe : (same as show)"
    echo -e "\tlist : list all available node groups"
    echo -e "\treboot [nodes space seperated] : Reboots the given group into it's default bos template."
    echo -e "\tshow [node] : show details on a specific node group"
    echo -e "\tshutdown [nodes space seperated] : shutdown all nodes in the group"
    echo -e "\tunconf : List all unconfigured nodes"
    
    exit 1
}
function node_list {
    refresh_ansible_groups
    for GROUP in "${!GROUP2NODES[@]}"; do
        echo "[$GROUP]"
        echo "nodes:               ${GROUP2NODES[$GROUP]}"
        echo
        echo
    done
}

function node_describe {
    local NODE="$1"
    local GROUP

    if [[ -z "$NODE" ]]; then
        echo "USAGE: $0 node show [node]"
        exit 1
    fi

    refresh_ansible_groups
    if [[ -z "${NODE2GROUP[$NODE]}" ]] ; then
       die "'$NODE' is not a valid node"
    fi
    GROUP="${NODE2GROUP[$NODE]}"
    image_defaults
    cluster_defaults_config
    if [[ -n "${BOS_DEFAULT[$GROUP]}" ]]; then
        

        CONFIG="${CUR_IMAGE_CONFIG[$GROUP]}"
        IMAGE_ETAG="${CUR_IMAGE_ETAG[$GROUP]}"

        IMAGE_NAME="${CUR_IMAGE_NAME[$GROUP]}"
        IMAGE_ID="${CUR_IMAGE_ID[$GROUP]}"

         echo "[$NODE]"
         echo "bos_sessiontemplate: ${BOS_DEFAULT[$GROUP]}"
         echo "recipe_id:           ${RECIPE_DEFAULT[$GROUP]}"
         echo "image_name:          $IMAGE_NAME"
         echo "image_id:            $IMAGE_ID"
         echo "config:              $CONFIG"
         echo "nodes:               $GROUP"
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$NODE]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"
         echo "nodes:               $GROUP"
    else
        die "'$NODE' is not a valid node."
    fi
    echo 
    echo "# CFS"
    RAW_CFS=$(cray cfs components describe "$NODE" --format json)
    echo -n "configurationStatus:  "
    echo "$RAW_CFS" | jq '.configurationStatus' | sed 's/"//g'
    echo -n "enabled:              "
    echo "$RAW_CFS" | jq '.enabled' | sed 's/"//g'
    echo -n "errorCount:           "
    echo "$RAW_CFS" | jq '.errorCount' | sed 's/"//g'
    echo -n "retryPolicy:          "
    echo "$RAW_CFS" | jq '.retryPolicy' | sed 's/"//g'
    
}

function node_boot {
    local ACTION="$1"
    shift
    local NODES=( "$@" )
    local GROUP
    if [[ -z "${NODES[0]}" ]]; then
        echo "USAGE: $0 node $ACTION [xnames]" 1>&2
        exit 1
    fi
    refresh_ansible_groups
    cluster_defaults_config
    declare -A REBOOT_GROUPS

    for NODE in "${NODES[@]}"; do
        if [[ -z "${NODE2GROUP[$NODE]}" ]]; then
            die "Error. Node '$NODE' is not a valid node"
        fi
        REBOOT_GROUPS[${NODE2GROUP[$NODE]}]+="$NODE "
    done
    
    for GROUP in ${!REBOOT_GROUPS[@]}; do
        NODES=$(echo "${REBOOT_GROUPS[*]}" | sed 's/ $//g' | sed 's/ /,/g')
        prompt "Ok to reboot GROUP '$GROUP' for nodes: $NODES?" "Yes" "No" || exit 0
        if [[ -z "${BOS_DEFAULT[$GROUP]}" ]]; then
            die "Group '$GROUP' is not assigned a bos template!"
        fi
        bos_boot "$ACTION" "${BOS_DEFAULT[$GROUP]}" "$NODES"
    done
}

function node_config {
    local NODES=( "$@" )
    local GROUP
    if [[ -z "${NODES[0]}" ]]; then
        echo "USAGE: $0 node config [xnames]" 1>&2
        exit 1
    fi
    refresh_ansible_groups
    cluster_defaults_config
    declare -A CONFIG_GROUPS

    for NODE in "${NODES[@]}"; do
        if [[ -z "${NODE2GROUP[$NODE]}" ]]; then
            die "Error. Node '$NODE' is not a valid node"
        fi
        CONFIG_GROUPS[${NODE2GROUP[$NODE]}]+="$NODE "
    done
    
    for GROUP in ${!CONFIG_GROUPS[@]}; do
        NODES=$(echo "${CONFIG_GROUPS[*]}" | sed 's/ $//g' | sed 's/ /,/g')
        echo "configuring nodes '$NODES' as group '$GROUP'..."
        if [[ -z "${CUR_IMAGE_CONFIG[$GROUP]}" ]]; then
            die "Group '$GROUP' is not assigned a bos template!"
        fi
        bos_boot configure "${BOS_DEFAULT[$GROUP]}" "$NODES"
    done
}
