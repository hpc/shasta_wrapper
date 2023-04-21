## node library
# Contains all commands for `shasta node`
# Actions for describing and performing actions against nodes

function node {
    case "$1" in
        2nid)
            shift
            node_2nid "$@"
            ;;
        2fullnid)
            shift
            node_2fullnid "$@"
            ;;
        2xname)
            shift
            node_2xname "$@"
            ;;
        boot)
            shift
            node_action boot "$@"
            ;;
        con*)
            shift
            node_config "$@"
            ;;
        clear_errors)
            shift
            node_clear_errors "$@"
            ;;
        disable)
            shift
            node_disable "$@"
            ;;
        enable)
            shift
            node_enable "$@"
            ;;
        power_on)
            shift
            power_action on "$@"
            exit $?
            ;;
        poweron)
            shift
            power_action on "$@"
            exit $?
            ;;
        power_off)
            shift
            power_action off "$@"
            exit $?
            ;;
        poweroff)
            shift
            power_action off "$@"
            exit $?
            ;;
        power_reset)
            shift
            power_reset "$@"
            exit $?
            ;;
        power_status)
            shift
            power_status "$@"
            exit $?
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
            node_action reboot "$@"
            ;;
        resetdb)
            shift
            node_reset_db
            ;;
        sho*)
            shift
            node_describe "$@"
            ;;
        sta*)
            shift
            node_status
            ;;
        shutdown)
            shift
            node_action shutdown "$@"
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
    echo -e "\t2nid [nodes] : Convert given nodes to nid numbers."
    echo -e "\t2fullnid [nodes] : Convert given nodes to nidXXXXXX format."
    echo -e "\t2xname [nodes] : Convert given nodes to xname format."
    echo -e "\tboot [nodes] : Boots the given nodes into the given group's default bos template."
    echo -e "\tconfig [nodes] : Configures the given nodes with the given group's default cfs config."
    echo -e "\tclear_errors [nodes] : Resets the node error counters to 0."
    echo -e "\tdescribe : (same as show)"
    echo -e "\tdisable [node] : Disable the node for hsm and cfs. Stops the node from being booted by bos, and cfs from running on it"
    echo -e "\tenable <options> [node] : Enable the node for hsm and cfs (or just cfs with the -c option). Allows the node from being booted by bos, and cfs to running on it. "
    echo -e "\tlist : List all available node groups"
    echo -e "\tpower_on <options> [nodes]: Power on given nodes"
    echo -e "\tpower_off <options> [nodes]: Power off given nodes"
    echo -e "\tpower_reset [nodes]: Reset node power"
    echo -e "\tpower_status [nodes]: Get node power status"
    echo -e "\treboot [nodes space-separated] : Reboots the given group into its default bos template."
    echo -e "\tresetdb : Clears the current database on what nodes are available and recomputes it. Useful after adding or removing nodes from a system(ie adding a cabinet)"
    echo -e "\tshow [node] : show details on a specific node group"
    echo -e "\tstatus : Show general hsm and cfs state of all nodes (slimmed down and faster sat status)"
    echo -e "\tshutdown [nodes] : Shutdown all nodes in the group"
    echo -e "\tunconf : List all unconfigured nodes"

    exit 1
}

## node_2xname
# Attempt to convert a given node name to its xname
function node_2xname {
    if [[ -z "$@" ]]; then
        echo "USAGE: $0 node 2xname [node list]"
        exit 1
    fi
    convert2xname "$@"
    echo "$RETURN"
}

## node_2nid
# Attempt to convert a given node name to its nid number
function node_2nid {
    if [[ -z "$@" ]]; then
        echo "USAGE: $0 node 2nid [node list]"
        exit 1
    fi
    convert2nid "$@"
    echo "$RETURN"
}

## node_2fullnid
# Attempt to convert a given node name to its fullnid
function node_2fullnid {
    if [[ -z "$@" ]]; then
        echo "USAGE: $0 node 2fullnid [node list]"
        exit 1
    fi
    convert2fullnid "$@"
    echo "$RETURN"
}

## node_list
# List out all nodes and their associated groups
function node_list {
    refresh_ansible_groups
    for GROUP in "${!GROUP2NODES[@]}"; do
        echo "[$GROUP]"
        echo "nodes:               ${GROUP2NODES[$GROUP]}"
        echo
        echo
    done
}

function node_reset_db {
    refresh_node_conversions_data
    echo "Node database has been refreshed"
}

function node_status {
    hsm_refresh_node_state
    refresh_ansible_groups
    local HSM_ENABLED HSM_STATE CFS_ENABLED CFS_STATE GROUP CFS_NODE_DATA

    local NODES=( "${!NODE2GROUP[@]}" )

    declare -A CFS_NODE_ENABLED CFS_NODE_STATE
    IFS=$'\n'
    CFS_NODE_DATA=( $(rest_api_query "cfs/v2/components" | jq -r '.[] | "\(.id) \(.enabled) \(.configurationStatus)"' ) )
    IFS=$' \t\n'
    for LINE in "${CFS_NODE_DATA[@]}"; do
        SPLIT=( $LINE )
        XNAME="${SPLIT[0]}"
        ENABLED="${SPLIT[1]}"
        STATE="${SPLIT[2]}"
        CFS_NODE_ENABLED[$XNAME]="$ENABLED"
        CFS_NODE_STATE[$XNAME]="$STATE"
    done
    printf "${COLOR_BOLD}%20s %13s %11s %13s %13s %20s${COLOR_RESET}\n" "NODE" "HSM_ENABLED" "HSM_STATE" "CFS_ENABLED" "CFS_STATE" "GROUPS"
    for NODE in "${NODES[@]}"; do
        HSM_ENABLED="${HSM_NODE_ENABLED[$NODE]}"
        HSM_STATE="${HSM_NODE_STATE[$NODE]}"
        CFS_ENABLED="${CFS_NODE_ENABLED[$NODE]}"
        CFS_STATE="${CFS_NODE_STATE[$NODE]}"
        GROUP="${NODE2GROUP[$NODE]}"

        printf "%20s %13s %11s %13s %13s %20s\n" "$NODE" "$HSM_ENABLED" "$HSM_STATE" "$CFS_ENABLED" "$CFS_STATE" "$GROUP"
    done | sort
}

## node_describe
# Show information on a given node
function node_describe {
    convert2xname "$@"
    local NODE="$RETURN"
    local GROUP

    if [[ -z "$NODE" ]]; then
        echo "USAGE: $0 node show [node]"
        exit 1
    fi

    hsm_refresh_node_state
    refresh_ansible_groups
    bos_get_default_node_group "$NODE"
    GROUP="$RETURN"
    image_defaults
    cluster_defaults_config
    echo "xname: ${CONVERT2XNAME[$NODE]}"
    echo "nid: ${CONVERT2FULLNID[$NODE]}"
    echo "nmn: ${CONVERT2NMN[$NODE]}"
    echo

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
         echo "groups:              $GROUP"
         echo "hsm_enabled          "
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$NODE]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"
         echo "groups:               $GROUP"
    else
        die "'$NODE' is not a valid node."
    fi
    echo
    echo "# HSM"
    hsm_node_describe "$NODE" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
    echo
    echo "# CFS"
    RAW_CFS=$(rest_api_query "cfs/v2/components/$NODE")
    echo -n "configurationStatus:  "
    echo "$RAW_CFS" | jq '.configurationStatus' | sed 's/"//g'
    echo -n "enabled:              "
    echo "$RAW_CFS" | jq '.enabled' | sed 's/"//g'
    echo -n "errorCount:           "
    echo "$RAW_CFS" | jq '.errorCount' | sed 's/"//g'
    echo -n "retryPolicy:          "
    echo "$RAW_CFS" | jq '.retryPolicy' | sed 's/"//g'

}
## node_config
# Rerun cfs configurations on given nodes
function node_config {
    OPTIND=1
    while getopts "y" OPTION ; do
        case "$OPTION" in
            y) ASSUME_YES=1;;
            \?) die 1 "cfs_apply:  Invalid option:  -$OPTARG" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "$@" ]]; then
        echo "USAGE: $0 node config [nodes]" 1>&2
        exit 1
    fi
    convert2xname "$@"
    local NODES=( $RETURN )
    cfs_clear_node_state "${NODES[@]}"
}

## node_clear_errors
function node_clear_errors {
    convert2xname "$@"
    local NODES=( $RETURN )
    local NODES_STRIPPED=( )
    hsm_get_node_state

    for node in "${NODES[@]}"; do
        if [[ "${HSM_NODE_ENABLED[$node]}" != "true" ]]; then
            continue
        fi
        if [[ "${HSM_NODE_STATE[$node]}" != "Ready" ]]; then
            continue
        fi
        NODES_STRIPPED+=( $node )
    done

    cfs_clear_node_counters "${NODES_STRIPPED[@]}"
}

## node_action
# Perform an action against a list of nodes. This figures out the correct bos template for the node and send that to bos_action with the node list.
function node_action {
    local ACTION="$1"
    local NODES GROUP TMP
    shift

    OPTIND=1
    while getopts "y" OPTION ; do
        case "$OPTION" in
            y) ASSUME_YES=1;;
            \?) die 1 "cfs_apply:  Invalid option:  -$OPTARG" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "$@" ]]; then
        echo "USAGE: $0 node $ACTION [xnames]" 1>&2
        exit 1
    fi
    if [[ -n "$NODES_CONVERTED" ]]; then
        NODES=( "$@" )
    else
        convert2xname "$@"
        NODES=( $RETURN )
    fi
    refresh_ansible_groups
    cluster_defaults_config
    declare -A ACTION_GROUPS

    # Organize nodes into their ansible groups that have a default bos config.
    for NODE in "${NODES[@]}"; do
        bos_get_default_node_group "$NODE"
        GROUP="$RETURN"
        ACTION_GROUPS[$GROUP]+="$NODE "
    done

    # Validate that the user really wants to do $ACTION against the nodes of this group
    for GROUP in ${!ACTION_GROUPS[@]}; do
        TMP="${ACTION_GROUPS[$GROUP]}"
        NODES=( $TMP )
        prompt_yn "Ok to $ACTION ${#NODES[@]} $GROUP nodes?" || unset ACTION_GROUPS[$GROUP]
    done

    # Perform the action
    for GROUP in ${!ACTION_GROUPS[@]}; do
        TMP="${ACTION_GROUPS[$GROUP]}"
        NODES=( $TMP )
        if [[ -z "${BOS_DEFAULT[$GROUP]}" ]]; then
            die "Group '$GROUP' is not assigned a bos template!"
        fi
        NODES_CONVERTED=1
        bos_action "$ACTION" "${BOS_DEFAULT[$GROUP]}" "${NODES[@]}"
    done
}


function node_enable {
    CFS_ONLY=0
    OPTIND=1
    while getopts "c" OPTION; do
        case "OPTION" in 
            c) CFS_ONLY=1;;
            \?) die 1 "cfs_apply: Invalid option: - $OPTARG"; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    local NODES=( $( nid2xname "$@") )
    if [[ -z "$NODES" ]]; then
        echo "USAGE: $0 node enable [nodelist]"
        exit 1
    fi

    if [ $CFS_ONLY -eq "0" ]; then 
        hsm_enable_nodes true "${NODES[@]}"
    fi
    cfs_enable_nodes true "${NODES[@]}"
}


function node_disable {
    local NODES=( $( nid2xname "$@") )

    if [[ -z "$NODES" ]]; then
        echo "USAGE: $0 node disable [nodelist]"
        exit 1
    fi

    hsm_enable_nodes false "${NODES[@]}"
    cfs_enable_nodes false "${NODES[@]}"
}
