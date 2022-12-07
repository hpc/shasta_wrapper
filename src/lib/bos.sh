## bos library
# Contains all commands for `shasta bos`
# This includes all bos job actions. Largely used for configuring bos and launching bos jobs to reboot/configure nodes.

BOS_CONFIG_DIR="/root/templates/"
BOS_TEMPLATES=( )
BOOT_LOGS="/var/log/boot/"`date +%y-%m-%dT%H-%M-%S`
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
        job*)
            shift
            bos_job "$@"
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
    echo -e "\tjob [action]: Manage bos jobs"
    echo -e "\tlist : show all bos session templates"
    echo -e "\treboot [template] [nodes|groups] : reboot a given node into the given bos template"
    echo -e "\tshutdown [template] [nodes|groups] : shutdown a given node into the given bos template"
    echo -e "\tshow [template] : show details of session template"

    exit 1
}

# refresh_bos_raw
# Pull down the raw json from bos and save it
function refresh_bos_raw {
    if [[ -n "$BOS_RAW" && "$1" != '--force' ]]; then
        return 0
    fi
    BOS_RAW=$(rest_api_query "bos/v1/sessiontemplate")
    if [[ -z "$BOS_RAW" ]]; then
       echo "Error retrieving bos data... Some information may be unavailable"
       return 1
    fi
    return 0
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
    die "Error. Node '$NODE' is not a member of any group defined for 'BOS_DEFAULT' in /etc/cluster_defaults.conf"
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
    if [[ -z "$BOS_LINES" ]]; then
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
    rest_api_query "bos/v1/sessiontemplate/$1"
    return $?
}

## bos_delete
# Delete the given bos config
function bos_delete {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 bos delete [bos config]"
	return 1
    fi
    rest_api_delete "bos/v1/sessiontemplate/$1"
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
    if [[ -n "$NODES_CONVERTED" ]]; then
        TARGET=( "$@" )
    elif [[ -n "$@" ]]; then
        convert2xname "$@"
    else
        echo "USAGE: $0 bos $ACTION [template] [target nodes or groups]" 1>&2
        exit 1
    fi

    local TARGET=( $RETURN )

    local KUBE_JOB_ID SPLIT BOS_SESSION POD LOGFILE TARGET_STRING
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')

    cluster_defaults_config
    #cfs_clear_node_counters "${TARGET[@]}"

    bos_exit_if_not_valid "$TEMPLATE"
    KUBE_JOB_ID=$(cray bos session create --operation "$ACTION" --template-uuid "$TEMPLATE" --limit "$TARGET_STRING"  --format json | jq '.links' | jq '.[].jobId' | grep -v null | sed 's/"//g')
    if [[ -z "$KUBE_JOB_ID" ]]; then
        die "Failed to create bos session"
    fi
    BOS_SESSION=$(echo "$KUBE_JOB_ID" | sed 's/^boa-//g')


    # if booting more than one node, just call it by the template name
    if [[ "${#TARGET}" -ge 2 ]]; then
        LOGFILE="$BOOT_LOGS/$ACTION-$TEMPLATE.log"
    else
        LOGFILE="$BOOT_LOGS/$ACTION-${TARGET[0]}.log"
    fi

    mkdir -p "$BOOT_LOGS"
    bos_job_log "$BOS_SESSION" > "$LOGFILE" 2>&1 &
    echo "$ACTION action initiated. details:"
    echo "BOS Session: $BOS_SESSION"
    echo "kubernetes pod: $POD"
    echo
    echo "Starting $ACTION..."
    echo "Boot Logs: '$LOGFILE'"
    echo
}
