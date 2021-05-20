#!/bin/bash
declare -A BOS_DEFAULT CONFIG_DEFAULT

CLUSTER_GROUPS=( )


function cluster {
    case $1 in
        gr*)
            shift
            cluster_group "$@"
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
    
    exit 1
}

function cluster_group {
    case $1 in
        li*)
            shift
            cluster_group_list "$@"
            ;;
        al*)
            shift
            cluster_group_all "$@"
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
    refresh_cluster_groups
    for group in "${!CONFIG_DEFAULT[@]}"; do
        echo $group
    done | sort
    for group in "${!BOS_DEFAULT[@]}"; do
        echo $group
    done | sort
}

function refresh_cluster_groups {
    local RAW
    if [[ -z "${!BOS_DEFAULT[@]}" ]]; then
        source /etc/cluster_defaults.conf
    fi
}

function cluster_group_all {
    refresh_cluster_groups
    
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
    refresh_cluster_groups

    local CONFIG IMAGE_ETAG BOS_RAW IMAGE
    if [[ -n "${BOS_DEFAULT[$GROUP]}" ]]; then
        BOS_RAW=$(cray bos sessiontemplate describe "${BOS_DEFAULT[$GROUP]}" --format json)

        echo "$BOS_RAW" > file
        CONFIG=$(echo "$BOS_RAW" | jq '.cfs.configuration' | sed 's/"//g')
        IMAGE_ETAG=$(echo "$BOS_RAW" | jq '.boot_sets.compute.etag' | sed 's/"//g')

        IMAGE_RAW=$(cray ims images list --format json | jq ".[] | select(.link.etag == \"$IMAGE_ETAG\")")
        IMAGE_NAME=$(echo "$IMAGE_RAW" | jq ". | \"\(.name)\"" | sed 's/"//g')
        IMAGE_ID=$(echo "$IMAGE_RAW" | jq ". | \"\(.id)\"" | sed 's/"//g')

         echo "[$GROUP]"
         echo "bos_sessiontemplate: ${BOS_DEFAULT[$GROUP]}"
         echo "image_name:          $IMAGE_NAME"
         echo "image_id:            $IMAGE_ID"
         echo "config:              $CONFIG"
    elif [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
         echo "[$GROUP]"
         echo "config:              ${CONFIG_DEFAULT[$GROUP]}"
    
    else
        echo "'$GROUP' is not a valid group."
        exit 2
    fi

}
