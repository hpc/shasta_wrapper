declare -A NODE2GROUP GROUP2NODES


function group {
    case "$1" in
        build_images)
            shift
            group_build_images "$@"
            ;;
        boot)
            shift
            group_action boot "$@"
            ;;
        conf*)
            shift
            group_action configure "$@"
            ;;
        li*)
            shift
            group_list "$@"
            ;;
        des*)
            shift
            group_describe "$@"
            ;;
        reboot)
            shift
            group_action reboot "$@"
            ;;
        sho*)
            shift
            group_describe "$@"
            ;;
        sum*)
            shift
            group_summary "$@"
            ;;
        shutdown)
            shift
            group_action shutdown "$@"
            ;;
        *)
            group_help
            ;;
    esac
}

function group_help {
    echo    "USAGE: $0 group [action]"
    echo    "DESC: shows the node groups information and what configurations, bos sessiontemplates, and images are used for each(details)"
    echo    "ACTIONS:"
    echo -e "\tboot [group] : Boots the nodes in the given group with the group's default bos template."
    echo -e "\tconfig [group] : Configures the nodes in the given group with the group's default cfs config."
    echo -e "\tbuild_images <--map> <group>: cluster node group information"
    echo -e "\tdescribe : (same as show)"
    echo -e "\tlist : list all available node groups"
    echo -e "\treboot [group] : Reboots the given group into it's default bos template."
    echo -e "\tshow : show details on a specific node group"
    echo -e "\tsummary <-v> : show all groups and their general configs"
    echo -e "\tshutdown [group] : shutdown all nodes in the group"

    exit 1
}

function group_list {
    local group
    cluster_defaults_config
    for group in "${!CONFIG_DEFAULT[@]}"; do
        echo $group
    done | sort
    for group in "${!BOS_DEFAULT[@]}"; do
        echo $group
    done | sort
}

function group_action {
    local ACTION="$1"
    local GROUP="$2"
    local NODES=""
    if [[ -z "$GROUP" ]]; then
        echo "USAGE: $0 group $ACTION [group]" 1>&2
        exit 1
    fi
    refresh_ansible_groups


    if [[ -z "${GROUP2NODES[$GROUP]}" ]]; then
        die "Group '$GROUP' is not a valid group" 1>&2
    fi
    NODES="${GROUP2NODES[$GROUP]}"
    node_action "$ACTION" $NODES
}

function refresh_ansible_groups {
    local ANSIBLE_LINES LINE SPLIT GROUP
    cluster_defaults_config

    if [[ -n "${!NODE2GROUP[@]}" ]]; then
        return
    fi

    IFS=$'\n'
    ANSIBLE_LINES=( $(cat /etc/ansible/hosts | grep -v 'hosts:$' | grep -v 'children:$' | grep -v 'all:$' | sed 's/: {}//g' | sed 's/ //g') )
    IFS=$' \t\n'

    GROUP=""
    for LINE in "${ANSIBLE_LINES[@]}"; do
        if [[ ${LINE: -1:1} == ':' && CUR_IMAGE_CONFIG[$${LINE:0:${#LINE}-1] ]]; then
            GROUP="${LINE:0:${#LINE}-1}"
        else
            NODE2GROUP[$LINE]+="$GROUP "
            GROUP2NODES[$GROUP]+="$LINE "
        fi
    done
}

function group_describe {
    local NO_NODES=0
    if [[ "$1" == "-q" ]]; then
        NO_NODES=1
        shift
    fi
    local GROUP="$1"
    local CONFIG IMAGE_ETAG IMAGE_NAME IMAGE_ID

    if [[ -z "$GROUP" ]]; then
        echo "USAGE: $0 group show [group]"
        exit 1
    fi

    cluster_defaults_config
    image_defaults
    refresh_ansible_groups

    local CONFIG IMAGE_ETAG BOS_RAW IMAGE
    if [[ -n "${BOS_DEFAULT[$GROUP]}" ]]; then


        CONFIG="${CUR_IMAGE_CONFIG[$GROUP]}"
        IMAGE_ETAG="${CUR_IMAGE_ETAG[$GROUP]}"

        IMAGE_NAME="${CUR_IMAGE_NAME[$GROUP]}"
        IMAGE_ID="${CUR_IMAGE_ID[$GROUP]}"

         echo "[$GROUP]"
         echo "bos_sessiontemplate: ${BOS_DEFAULT[$GROUP]}"
         echo "recipe_id:           ${RECIPE_DEFAULT[$GROUP]}"
         echo "image_name:          $IMAGE_NAME"
         echo "image_id:            $IMAGE_ID"
         echo "config:              $CONFIG"
         if [[ "$NO_NODES" -eq "0" ]]; then
             echo "nodes:               ${GROUP2NODES[$GROUP]}"
         fi
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$GROUP]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"
         if [[ "$NO_NODES" -eq "0" ]]; then
             echo "nodes:               ${GROUP2NODES[$GROUP]}"
         fi
    else
        die "'$GROUP' is not a valid group."
    fi
}


function group_build_images {
    local MAP="1"
    if [[ "$1" == "--map" ]]; then
        MAP="0"

        shift
    fi
    local GROUP="$1"
    local MAP_TARGET

    echo "## Validating current setup before trying to build anything... (Should take a few seconds)"
    cluster_defaults_config
    cluster_validate
    echo "Done"
    echo


    echo "## Launching Image Build(s)"
    if [[ -n "$GROUP" ]]; then
        if [[ -z "${RECIPE_DEFAULT[$GROUP]}" ]]; then
            die "Group '$GROUP' is not valid."
        fi
        if [[ "$MAP" -eq "0" ]]; then
            MAP_TARGET="${BOS_DEFAULT[$GROUP]}"
        fi
        image_build \
          "${RECIPE_DEFAULT[$GROUP]}" \
          "$GROUP" \
          "${CUR_IMAGE_CONFIG[$GROUP]}" \
          "${IMAGE_DEFAULT_NAME[$GROUP]}" \
          "$MAP_TARGET" &
    else
        for GROUP in "${!BOS_DEFAULT[@]}"; do
            if [[ "$MAP" -eq "0" ]]; then
                MAP_TARGET="${BOS_DEFAULT[$GROUP]}"
            fi
            image_build \
              "${RECIPE_DEFAULT[$GROUP]}" \
              "$GROUP" \
              "${CUR_IMAGE_CONFIG[$GROUP]}" \
              "${IMAGE_DEFAULT_NAME[$GROUP]}" \
              "$MAP_TARGET" &
        done
    fi
    echo "See detailed logs in: $IMAGE_LOGDIR/"
    echo -n "Images started building at: "
    date

    wait $(jobs -p)
    echo -n "Images stopped building at: "
    date

}

function group_summary {
    local ARGS='-q'
    if [[ "$1" == "-v" ]]; then
        ARGS=''
    fi
    local group
    cluster_defaults_config

    for group in "${!CONFIG_DEFAULT[@]}"; do
        group_describe $ARGS "$group"
        echo ""
    done
    for group in "${!BOS_DEFAULT[@]}"; do
        group_describe $ARGS "$group"
        echo ""
    done
}
