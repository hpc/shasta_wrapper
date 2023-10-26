## bos library
# Contains all commands for `shasta bos`
# Largely used for configuring bos and launching bos jobs to reboot/configure nodes.

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

BOS_CONFIG_DIR="/root/templates/"
BOS_TEMPLATES=( )
BOS_RAW=""

function bos {
    case "$1" in
        clo*)
            shift
            bos_clone "$@"
            ;;
        boot)
            shift
            bos_action boot "$@"
            ;;
        config*)
            shift
            bos_action configure "$@"
            ;;
        delete)
            shift
            bos_delete "$@"
            ;;
        des*)
            shift
            bos_describe "$@"
            ;;
        ed*)
            shift
            bos_edit "$@"
            ;;
        li*)
            shift
            bos_list "$@"
            ;;
        reboot)
            shift
            bos_action reboot "$@"
            ;;
        sho*)
            shift
            bos_describe "$@"
            ;;
        shutdown)
            shift
            bos_action shutdown "$@"
            ;;
        stage)
            shift
            bos_action stage "$@"
            ;;
        sum*)
            shift
            bos_summary "$@"
            ;;
        *)
            bos_help
            ;;
    esac
}

function bos_help {
    echo    "USAGE: $0 bos [action]"
    echo    "DESC: bos sessiontemplates define the boot parameters, image, and config to use at boot. Direct access to these can be achieved via 'cray bos sessiontemplate'"
    echo    "ACTIONS:"
    echo -e "\tboot [template] [nodes|groups] : boot a given node into the given bos template"
    echo -e "\tclone [src] [dest] : copy an existing template to a new one with a different name"
    echo -e "\tconfig [template] [nodes|groups] : Configure the given nodes with the given bos template"
    echo -e "\tedit [template] : edit a bos session template"
    echo -e "\tdescribe [template] : (same as show)"
    echo -e "\tlist : show all bos session templates"
    echo -e "\treboot [template] [nodes|groups] : reboot a given node into the given bos template"
    echo -e "\tshutdown [template] [nodes|groups] : shutdown a given node into the given bos template"
    echo -e "\tshow [template] : show details of session template"
    echo -e "\tstage [template] [nodes|groups] : Set image in bos template to be used at next boot for given nodes"
    echo -e "\tsummary <-v> : Show node states that bos is working through"

    exit 1
}

# refresh_bos_raw
# Pull down the raw json from bos and save it
function refresh_bos_raw {
    if [[ -n "$BOS_RAW" && "$1" != '--force' ]]; then
        return 0
    fi
    BOS_RAW=$(rest_api_query "bos/v2/sessiontemplates")
    if [[ -z "$BOS_RAW" || $? -ne 0 ]]; then
       error "${COLOR_RED}Error retrieving bos data: $BOS_RAW"
       BOS_RAW=""
       return 1
    fi
    return 0
}

## bos_component_refresh
# Refresh current node info from bos
function bos_component_refresh {
    if [[ -n "${BOS_JOBS[0]}" && "$1" != "--force" ]]; then
        return
    fi
    local RET=1
    BOS_NODE_RAW=$(rest_api_query "bos/v2/components")
    if [[ -z "$BOS_NODE_RAW" || $? -ne 0 ]]; then
       error "Error retrieving bos data: $BOS_NODE_RAW"
       return 1
    fi
}

## bos_summary
function bos_summary {
    local VERBOSE=0 NODE NODE_RAW SPLIT STATE CONDENSED_NODES
    declare -a NODE_STATES
    declare -A NODE_STATE_HASH
    OPTIND=1
    while getopts "v" OPTION ; do
        case "$OPTION" in
            v) VERBOSE=1
            ;;
            \?) echo "USAGE: $0 bos summary <OPTIONS>"
                echo "OPTIONS: "
                echo -e "\t-v - Output the node names instead of the count"
                return 1
            ;;
        esac
    done
    setup_craycli

    shift $((OPTIND-1))

    bos_component_refresh
    #echo "$BOS_NODE_RAW"
    #return
    if [[ $VERBOSE -eq 0 ]]; then
	    echo "$BOS_NODE_RAW" | jq -r '.[] | "\(.status.status)/\(.status.phase)"' | sort | uniq -c
    else
        IFS=$'\n'
	NODE_STATES=( $(echo "$BOS_NODE_RAW" | jq -r '.[] | "\(.id) \(.status.status)/\(.status.phase)"') )
        IFS=$' \t\n'
	for NODE_RAW in "${NODE_STATES[@]}"; do
            SPLIT=( $NODE_RAW )
            NODE="${SPLIT[0]}"
            STATE="${SPLIT[1]}"
	    if [[ -z $STATE ]]; then
	        STATE='NoAction'
	    fi

	    if [[ -z "${NODE_STATE_HASH[$STATE]}" ]]; then
	        NODE_STATE_HASH[$STATE]="$NODE"
            else
	        NODE_STATE_HASH[$STATE]+=",$NODE"
            fi
	done

	STATES_SORTED=$(echo "${!NODE_STATE_HASH[@]}" | sort)
        for STATE in $STATES_SORTED; do
            convert2fullnid "${NODE_STATE_HASH[$STATE]}"
	    CONDENSED_NODES=$(nodeset -f $RETURN)
	    printf '%40s %s\n' "$STATE" "$CONDENSED_NODES"
	done
    fi
}

## bos_get_default_node_group
# Get the group to use for the given node. This is done due to some ansible groups not having any defaults for booting, thus for this we are looking for what group to consider the node from the list of groups that have assigned default bos templates.
function bos_get_default_node_group {
    local NODE="$1"
    cluster_defaults_config
    refresh_ansible_groups

    if [[ -z "${NODE2GROUP[$NODE]}" ]]; then
        die "Error. Node '$NODE' is not a valid node"
    fi

    # This is needed to split it by space
    GROUP_LIST="${NODE2GROUP[$NODE]}"
    for GROUP in $GROUP_LIST; do
        if [[ -n "${BOS_DEFAULT[$GROUP]}" ]]; then
            RETURN="$GROUP"
            return
        fi
        if [[ -n "${CONFIG_DEFAULT[$GROUP]}" ]]; then
            RETURN="$GROUP"
            return
        fi
    done
    die "Error. Node '$NODE' is not a member of any group defined for 'BOS_DEFAULT' in /etc/shasta_wrapper/cluster_defaults.conf"
}

## bos_list
# List the given bos configurations
function bos_list {
    local BOS_LINES line group
    cluster_defaults_config
    refresh_bos_raw
    echo "NAME(Nodes applied to at boot)"

    # Grab the bos config names
    BOS_LINES=( $(echo "$BOS_RAW" | jq '.[].name' | sed 's/"//g') )
    if [[ -z "$BOS_RAW" ]]; then
        die "Error unable to get bos information"
    fi

    # When a bos template is set as default for an ansible group, display that
    # ansible group in bold in paratheses next to it
    BOS_TEMPLATES=( )
    for line in "${BOS_LINES[@]}"; do
        echo -n "$line"
        BOS_TEMPLATES+=( $line )
        for group in "${!BOS_DEFAULT[@]}"; do
            if [[ "${BOS_DEFAULT[$group]}" == "$line" ]]; then
                 echo -n "$COLOR_BOLD($group)$COLOR_RESET"
            fi
        done
        echo
    done
}

## bos_describe
# Show the bos configuration for the given bos config
function bos_describe {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 bos describe [bos config]"
	return 1
    fi
    rest_api_query "bos/v2/sessiontemplates/$1"
    return $?
}

## bos_delete
# Delete the given bos config
function bos_delete {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 bos delete [bos config]"
	return 1
    fi
    rest_api_delete "bos/v2/sessiontemplates/$1"
    return $?
}

## bos_exit_if_not_valid
# Exit if the given bos template isn't valid (most likely it doesn't exist)
function bos_exit_if_not_valid {
    bos_describe "$1" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "Error! $1 is not a valid bos sessiontemplate."
    fi
}

## bos_exit_if_exists
# Exit if the given bos config exists
function bos_exit_if_exists {
    bos_describe "$1" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "'$1' already exists. If you really want to overwrite it, you need to delete it first"
        exit 1
    fi
}

## bos_clone
# Clone the given bos template to annother name (won't replace existing ones)
function bos_clone {
    local SRC="$1"
    local DEST="$2"
    local TEMPFILE
    setup_craycli

    if [[ -z "$SRC" || -z "$DEST" ]]; then
        echo "USAGE: $0 bos clone [src bos template] [dest bos template]" 1>&2
        exit 1
    fi
    bos_exit_if_not_valid "$SRC"
    bos_exit_if_exists "$DEST"

    set -e
    tmpdir
    TMPFILE="$TMPDIR/bos_sessiontemplate.json"

    bos_describe $SRC > "$TMPFILE"

    cray bos sessiontemplate create --name $DEST --file "$TMPFILE" --format json
    set +e
}

## bos_update_template
# updatei a key/value pair in the given bos config
function bos_update_template {
    local TEMPLATE="$1"
    local KEY="$2"
    local VALUE="$3"
    setup_craycli

    set -e
    bos_describe "$TEMPLATE" > "$BOS_CONFIG_DIR/$TEMPLATE.json"
    json_set_field "$BOS_CONFIG_DIR/$TEMPLATE.json" "$KEY" "$VALUE"
    cray bos sessiontemplate create --name $TEMPLATE --file "$BOS_CONFIG_DIR/$TEMPLATE.json" > /dev/null 2>&1
    bos_describe "$TEMPLATE" > "$BOS_CONFIG_DIR/$TEMPLATE.json"
    cat "$BOS_CONFIG_DIR/$TEMPLATE.json" | jq "$KEY" > /dev/null
    set +e
    return $?
}

## bos_edit
# Edit the given bos template file with an editor
function bos_edit {
    local CONFIG="$1"
    setup_craycli

    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 bos edit [bos template]" 1>&2
        exit 1
    fi
    bos_exit_if_not_valid "$CONFIG"

    set -e
    bos_describe $CONFIG > "$BOS_CONFIG_DIR/$CONFIG.json"

    if [[ ! -s "$BOS_CONFIG_DIR/$CONFIG.json" ]]; then
        rm -f "$BOS_CONFIG_DIR/$CONFIG.json"
        die "Error! Failed to get bos config '$CONFIG'!"
    fi

    set +e
    edit_file "$BOS_CONFIG_DIR/$CONFIG.json" 'json'
    if [[ "$?" == 0 ]]; then
        echo -n "Updating '$CONFIG' with new data..."
        verbose_cmd cray bos sessiontemplate create --name $CONFIG --file "$BOS_CONFIG_DIR/$CONFIG.json" --format json > /dev/null 2>&1
        echo 'done'
    else
        echo "No modifications made. Not pushing changes up"
    fi
}

## bos_action
# Perform a given action with the given bos template against the given nodes.
# For example, reboot some nodes with the cos-sessiontemplate.
function bos_action {
    local ACTION="$1"
    shift
    local TEMPLATE="$1"
    shift
    local TARGET=(  )
    local STAGE ARGS
    if [[ -n "$NODES_CONVERTED" ]]; then
        TARGET=( "$@" )
    elif [[ -n "$@" ]]; then
        convert2xname "$@"

        TARGET=( $RETURN )
    else
        echo "USAGE: $0 bos $ACTION [template] [target nodes or groups]" 1>&2
        exit 1
    fi
    setup_craycli

    if [[ "$ACTION" == "stage" ]]; then
        ACTION='reboot'
	STAGE=1
	ARGS+=" --stage true"
    fi

    local KUBE_JOB_ID SPLIT BOS_SESSION POD LOGFILE TARGET_STRING
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')

    cluster_defaults_config
    #cfs_clear_node_counters "${TARGET[@]}"

    bos_exit_if_not_valid "$TEMPLATE"
    set -x
    BOS_SESSION=$(cray bos v2 sessions create $ARGS --operation "$ACTION" --template-name "$TEMPLATE" --limit "$TARGET_STRING"  --format json | jq '.name' | grep -v null | sed 's/"//g')
    if [[ -z "$BOS_SESSION" ]]; then
        die "Failed to create bos session"
    fi

    if [[ -n $STAGE ]]; then
        echo "stage action initiated."
    else
        echo "$ACTION action initiated."
    fi
    echo "BOS Session: $BOS_SESSION"
    echo
}

