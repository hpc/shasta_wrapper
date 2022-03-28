function node {
    case "$1" in
        boot)
            shift
            node_ boot "$@"
            ;;
        con*)
            shift
            node_action configure "$@"
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
        sho*)
            shift
            node_describe "$@"
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
    convert2xname "$@"
    local NODE="$RETURN"
    local GROUP

    if [[ -z "$NODE" ]]; then
        echo "USAGE: $0 node show [node]"
        exit 1
    fi

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
         echo "groups:               $GROUP"
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$NODE]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"
         echo "groups:               $GROUP"
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

function node_action {
    local ACTION="$1"
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
    convert2xname "$@"
    local NODES=( $RETURN )
    local GROUP TMP
    refresh_ansible_groups
    cluster_defaults_config
    declare -A ACTION_GROUPS

    for NODE in "${NODES[@]}"; do
        bos_get_default_node_group "$NODE"
        GROUP="$RETURN"
        ACTION_GROUPS[$GROUP]+="$NODE "
    done
    for GROUP in ${!ACTION_GROUPS[@]}; do
        TMP="${ACTION_GROUPS[$GROUP]}"
        NODES=( $TMP )
        prompt_yn "Ok to $ACTION ${#NODES[@]} $GROUP nodes?" || unset ACTION_GROUPS[$GROUP]
    done

    for GROUP in ${!ACTION_GROUPS[@]}; do
        TMP="${ACTION_GROUPS[$GROUP]}"
        NODES=( $TMP )
        if [[ -z "${BOS_DEFAULT[$GROUP]}" ]]; then
            die "Group '$GROUP' is not assigned a bos template!"
        fi
        bos_action "$ACTION" "${BOS_DEFAULT[$GROUP]}" "${NODES[@]}"
    done
}
