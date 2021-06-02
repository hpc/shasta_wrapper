#!/bin/bash
declare -A BOS_DEFAULT CONFIG_DEFAULT RECIPE_DEFAULT IMAGE_DEFAULT_NAME CUR_IMAGE_ID CUR_IMAGE_NAME CUR_IMAGE_ETAG CUR_IMAGE_CONFIG
CLUSTER_GROUPS=( )


function cluster {
    case $1 in
        build_images)
            shift
            cluster_build_images "$@"
            ;;
        gr*)
            shift
            cluster_group "$@"
            ;;
        reboot_group)
            shift
            cluster_reboot_group "$@"
            ;;
        reboot_nodes)
            shift
            cluster_reboot_nodes "$@"
            ;;
        val*)
            shift
            cluster_validate "$@"
            ;;
        *)
            cluster_help
            ;;
    esac
}

function cluster_help {
    echo    "USAGE: $0 cluster [action]"
    echo    "DESC: shows general cluster information. Such as the node groups there are and what configurations, bos sessiontemplates, and images are used for each. Groups are defined in /etc/bos_defaults.conf inking each to a bos sessiontemplate."
    echo    "ACTIONS:"
    echo -e "\tgroup : cluster node group information"
    echo -e "\tbuild_images <--map> <group>: cluster node group information"
    echo -e "\treboot_group [group] : Reboots the given group into it's default bos template."
    echo -e "\treboot_nodes [group] [nodes] : Reboots the given nodes in a specific group into the group's default bos template."
    echo -e "\tvalidate : Check that current defaults and their bos configurations actually point to things that exist."

    exit 1
}

function cluster_group {
    case $1 in
        al*)
            shift
            cluster_group_all "$@"
            ;;
        li*)
            shift
            cluster_group_list "$@"
            ;;
        des*)
            shift
            cluster_group_describe "$@"
            ;;
        sh*)
            shift
            cluster_group_describe "$@"
            ;;
        *)
            cluster_group_help
            ;;
    esac
}

function cluster_build_images {
    local MAP="1"
    if [[ "$1" == "--map" ]]; then
        MAP="0"

        shift
    fi
    local GROUP="$1"

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

function cluster_group_help {
    echo    "USAGE: $0 cluster group [action]"
    echo    "DESC: shows the node groups information and what configurations, bos sessiontemplates, and images are used for each(details)"
    echo    "ACTIONS:"
    echo -e "\tall : show all groups and thair confits"
    echo -e "\tdescribe : (same as show)"
    echo -e "\tlist : list all available node groups"
    echo -e "\tshow : show details on a specific node group"

    exit 1
}

function cluster_group_list {
    cluster_defaults_config
    for group in "${!CONFIG_DEFAULT[@]}"; do
        echo $group
    done | sort
    for group in "${!BOS_DEFAULT[@]}"; do
        echo $group
    done | sort
}

function cluster_defaults_config {
    local IMAGE_RAW BOS_RAW ALL_BOS_RAW
    if [[ -n "${!BOS_DEFAULT[@]}" ]]; then
        return 0
    fi
    source /etc/cluster_defaults.conf
    ALL_BOS_RAW=$(cray bos sessiontemplate list --format json)
    for group in "${!BOS_DEFAULT[@]}"; do
        BOS_RAW=$(echo "$ALL_BOS_RAW" | jq ".[] | select(.name == \"${BOS_DEFAULT[$group]}\")")

        if [[ -z "$BOS_RAW" ]]; then
            die "Error: default BOS_DEFAULT '${BOS_DEFAULT[$group]}' set for group '$group' is not a valid  bos sessiontemplate. Check /etc/cluster_defaults.conf" 1>&2
        fi

        CUR_IMAGE_CONFIG[$group]=$(echo "$BOS_RAW" | jq '.cfs.configuration' | sed 's/"//g')
        CUR_IMAGE_ETAG[$group]=$(echo "$BOS_RAW" | jq '.boot_sets.compute.etag' | sed 's/"//g')

        IMAGE_RAW=$(cray ims images list --format json | jq ".[] | select(.link.etag == \"${CUR_IMAGE_ETAG[$group]}\")")
        if [[ -z "$IMAGE_RAW" ]]; then
            die "Error. Image etag '${CUR_IMAGE_ETAG[$group]}' for bos sessiontemplate '${BOS_DEFAULT[$group]}' does not exist." 1>&2
        fi
        CUR_IMAGE_NAME[$group]=$(echo "$IMAGE_RAW" | jq ". | \"\(.name)\"" | sed 's/"//g')
        CUR_IMAGE_ID[$group]=$(echo "$IMAGE_RAW" | jq ". | \"\(.id)\"" | sed 's/"//g')
    done
}

function cluster_validate {
    cluster_defaults_config

    local CONFIG_RAW CONFIG RECIPE_RAW RECIPE
    CONFIG_RAW=$(cray cfs configurations list --format json)
    RECIPE_RAW=$(cray ims recipes list --format json)
    for group in "${!BOS_DEFAULT[@]}"; do
        echo -n "Checking $group..."
        # Validate recipe used exists
        RECIPE=$(echo "$RECIPE_RAW" | jq ".[] | select(.id == \"${RECIPE_DEFAULT[$group]}\")")
        if [[ -z "$RECIPE" ]]; then
            echo
            die "Error config '${RECIPE_DEFAULT[$group]}' set for group '$group' is not a valid recipe. Check config defaults /etc/cluster_defaults.conf."
        fi
        # Validate configuration used exists
        CONFIG=$(echo "$CONFIG_RAW" | jq ".[] | select(.name == \"${CUR_IMAGE_CONFIG[$group]}\")")
        if [[ -z "$CONFIG" ]]; then
            echo
            die "Error config '${CUR_IMAGE_CONFIG[$group]}' set in bos sessiontemplate '${BOS_DEFAULT[$group]}' is not a valid configuration. check bos configuration."
        fi
        echo "ok"
    done
}

function cluster_group_all {
    cluster_defaults_config

    for group in "${!CONFIG_DEFAULT[@]}"; do
        cluster_group_describe "$group"
        echo ""
    done
    for group in "${!BOS_DEFAULT[@]}"; do
        cluster_group_describe "$group"
        echo ""
    done
}

function cluster_group_describe {
    local GROUP=$1
    cluster_defaults_config

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
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$GROUP]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"

    else
        die "'$GROUP' is not a valid group."
    fi

}

function cluster_reboot_group {
    GROUP="$1"
    if [[ -z "$GROUP" ]]; then
        echo "USAGE: $0 cluster reboot_group [group]" 1>&2
        exit 1
    fi
    cluster_defaults_config


    if [[ -z "${BOS_DEFAULT[$GROUP]}" ]]; then
        die "Group '$GROUP' is not a valid group" 1>&2
    fi
    bos_reboot "${BOS_DEFAULT[$GROUP]}" "$GROUP"
}


function cluster_reboot_nodes {
    local GROUP="$1"
    local NODES="$2"
    if [[ -z "$GROUP" ]]; then
        die "USAGE: $0 cluster reboot_group [group] [nodes]" 1>&2
    fi
    cluster_defaults_config


    if [[ -z "${BOS_DEFAULT[$GROUP]}" ]]; then
        die "Group '$GROUP' is not a valid group" 1>&2
    fi
    bos_reboot "${BOS_DEFAULT[$GROUP]}" "$NODES"
}
