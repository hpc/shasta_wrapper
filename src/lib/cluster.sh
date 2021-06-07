#!/bin/bash
declare -A BOS_DEFAULT CONFIG_DEFAULT RECIPE_DEFAULT IMAGE_DEFAULT_NAME CUR_IMAGE_ID CUR_IMAGE_NAME CUR_IMAGE_ETAG CUR_IMAGE_CONFIG
CLUSTER_GROUPS=( )


function cluster {
    case "$1" in
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
    echo    "DESC: shows general cluster information. Such as the node groups there are and what configurations, bos sessiontemplates, and images are used for each. Groups are defined in /etc/bos_defaults.conf linking each to a bos sessiontemplate."
    echo    "ACTIONS:"
    echo -e "\tvalidate : Check that current defaults and their bos configurations actually point to things that exist."

    exit 1
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
            echo "Error. Image etag '${CUR_IMAGE_ETAG[$group]}' for bos sessiontemplate '${BOS_DEFAULT[$group]}' does not exist." 1>&2
            CUR_IMAGE_NAME[$group]="Invalid"
            CUR_IMAGE_ID[$group]="Invalid"
        else
            CUR_IMAGE_NAME[$group]=$(echo "$IMAGE_RAW" | jq ". | \"\(.name)\"" | sed 's/"//g')
            CUR_IMAGE_ID[$group]=$(echo "$IMAGE_RAW" | jq ". | \"\(.id)\"" | sed 's/"//g')
        fi
    done
    for group in "${!CONFIG_DEFAULT[@]}"; do
        CUR_IMAGE_CONFIG[$group]="${CONFIG_DEFAULT[$group]}"
    done
}

function cluster_validate {
    local group RECIPE CONFIG
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
