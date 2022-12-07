## hsm library
# Contains all commands for `shasta hsm`
# Used for managing node hardware state

declare -A HSM_NODE_ENABLED
declare -A HSM_NODE_STATE

## hsm_get_node_state
function hsm_get_node_state {
    if [[ -z "${HSM_NODE_ENABLED[@]}" ]]; then
        hsm_refresh_node_state
    fi
}

## hsm_refresh_node_state
function hsm_refresh_node_state {
    local LINE
    IFS=$'\n'
    local LINES=( $(rest_api_query smd/hsm/v2/State/Components | jq -r '.[][] | "\(.ID) \(.Enabled) \(.State)"') )
    IFS=$' \t\n'
    for LINE in "${LINES[@]}"; do
        SPLIT=( $LINE )
        XNAME="${SPLIT[0]}"
        ENABLED="${SPLIT[1]}"
        STATE="${SPLIT[2]}"
        HSM_NODE_ENABLED[$XNAME]="$ENABLED"
        HSM_NODE_STATE[$XNAME]="$STATE"
    done
}

function hsm_node_describe {
    NODE="$1"

    rest_api_query smd/hsm/v2/State/Components | jq ".[][] | select(.ID == \"$NODE\")"
}

## hsm_enable_nodes
# Enable/disable the given nodes in hms
function hsm_enable_nodes {
    local STATE="$1"
    shift
    local NODES=( "$@" )
    local NODE i
    if [[ -z "${NODES[@]}" ]]; then
        die "hms_enable: ERROR! No node given!"
    fi
    if [[ -z "$STATE" ]]; then
        die "hms_enable: ERROR! No state given!"
    fi
    # We do this one at a time as smd can't seem to handle lots of connections well
    i=1
    for NODE in "${NODES[@]}"; do
        echo -en "\rUpdating hsm state: $i/${#NODES[@]}"
        rest_api_patch "smd/hsm/v2/State/Components/$NODE/Enabled" "{ \"Enabled\": $STATE }"  > /dev/null 2>&1
        (( i++ ))
    done
    echo

    #wait_for_background_tasks "Updating hsm state" "${#NODES[@]}"
}
