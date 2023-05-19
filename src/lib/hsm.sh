## hsm library
# Contains all commands for `shasta hsm`
# Used for managing node hardware state

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

declare -A HSM_NODE_ENABLED
declare -A HSM_NODE_STATE
declare -A HSM_NODE_GROUP

## hsm_get_node_state
function hsm_get_node_state {
    if [[ -z "${HSM_NODE_ENABLED[@]}" ]]; then
        hsm_refresh_node_state
    fi
}

## hsm_refresh_node_state
function hsm_refresh_node_state {
    local LINE XNAME NID ENABLED STATE
    IFS=$'\n'
    local LINES=( $(rest_api_query smd/hsm/v2/State/Components |  jq '.[][] | select(.Type == "Node")' | jq -r '. | "\(.ID) \(.NID) \(.Enabled) \(.State) \(.Role) \(.SubRole)"') )
    IFS=$' \t\n'
    for LINE in "${LINES[@]}"; do
        SPLIT=( $LINE )
        XNAME="${SPLIT[0]}"
        NID="${SPLIT[1]}"
        ENABLED="${SPLIT[2]}"
        STATE="${SPLIT[3]}"
        ROLE="${SPLIT[4]}"
        SUBROLE="${SPLIT[5]}"

        if [[ "$NID" != 'null' ]]; then
            CONVERT2NID[$XNAME]="$NID"
            CONVERT2XNAME[$NID]="$XNAME"
        fi
        HSM_NODE_ENABLED[$XNAME]="$ENABLED"
        HSM_NODE_STATE[$XNAME]="$STATE"

	if [[ "$SUBROLE" == "null" ]]; then
            HSM_NODE_GROUP[$XNAME]="$ROLE"
	else
            HSM_NODE_GROUP[$XNAME]="$ROLE ${ROLE}_${SUBROLE}"
	fi
        NODE2GROUP[$XNAME]="${HSM_NODE_GROUP[$XNAME]}"
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
    local NODE I
    if [[ -z "${NODES[@]}" ]]; then
        die "hms_enable: ERROR! No node given!"
    fi
    if [[ -z "$STATE" ]]; then
        die "hms_enable: ERROR! No state given!"
    fi
    # We do this one at a time as smd can't seem to handle lots of connections well
    I=1
    for NODE in "${NODES[@]}"; do
        echo -en "\rUpdating hsm state: $I/${#NODES[@]}"
        rest_api_patch "smd/hsm/v2/State/Components/$NODE/Enabled" "{ \"Enabled\": $STATE }"  > /dev/null 2>&1
        (( I++ ))
    done
    echo

    #wait_for_background_tasks "Updating hsm state" "${#NODES[@]}"
}

