
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
        config*)
            shift
            bos_boot configure "$@"
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
            bos_boot reboot "$@"
            ;;
        sh*)
            shift
            bos_describe "$@"
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
    echo -e "\tclone [src] [dest] : copy an existing template to a new one with a different name"
    echo -e "\tconfig [nodes|groups] : Configure the given nodes"
    echo -e "\tedit [template] : edit a bos session template"
    echo -e "\tdescribe [template] : (same as show)"
    echo -e "\tlist : show all bos session templates"
    echo -e "\treboot [template] [nodes|groups] : reboot a given node into the given bos template"
    echo -e "\tshow [template] : show details of session template"

    exit 1
}

function refresh_bos_raw {
    if [[ -n "$BOS_RAW" && "$1" != '--force' ]]; then
        return 0
    fi
    BOS_RAW=$(cray bos sessiontemplate list --format json)
    if [[ -z "$BOS_RAW" ]]; then
       echo "Error retrieving bos data... Some information may be unavailable"
       return 1
    fi
    return 0
}

function bos_list {
    local BOS_LINES line group
    cluster_defaults_config
    refresh_bos_raw
    echo "NAME(Nodes applied to at boot)"
    BOS_LINES=( $(echo "$BOS_RAW" | jq '.[].name' | sed 's/"//g') )
    if [[ -z "$BOS_LINES" ]]; then
        die "Error unable to get bos information"
    fi
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

function bos_describe {
    cray bos sessiontemplate describe "$@"
    return $?
}

function bos_delete {
    cray bos sessiontemplate delete "$@"
    return $?
}

function bos_exit_if_not_valid {
    bos_describe "$1" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "Error! $1 is not a valid bos sessiontemplate."
    fi
}

function bos_exit_if_exists {
    bos_describe "$1" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "'$1' already exists. If you really want to overwrite it, you need to delete it first"
        exit 1
    fi
}

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

    bos_describe $SRC --format json > "$TMPFILE"

    cray bos sessiontemplate create --name $DEST --file "$TMPFILE" --format json
    set +e
}

function bos_update_template {
    local TEMPLATE="$1"
    local KEY="$2"
    local VALUE="$3"

    set -e
    bos_describe "$TEMPLATE" --format json > "$BOS_CONFIG_DIR/$TEMPLATE.json"
    json_set_field "$BOS_CONFIG_DIR/$TEMPLATE.json" "$KEY" "$VALUE"
    cray bos sessiontemplate create --name $TEMPLATE --file "$BOS_CONFIG_DIR/$TEMPLATE.json" --format json > /dev/null 2>&1
    bos_describe "$TEMPLATE" --format json > "$BOS_CONFIG_DIR/$TEMPLATE.json"
    cat "$BOS_CONFIG_DIR/$TEMPLATE.json" | jq "$KEY" > /dev/null
    set +e
    return $?
}

function bos_edit {
    local CONFIG="$1"

    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 bos edit [bos template]" 1>&2
        exit 1
    fi
    bos_exit_if_not_valid "$CONFIG"

    set -e
    bos_describe $CONFIG --format json > "$BOS_CONFIG_DIR/$CONFIG.json"

    if [[ ! -s "$BOS_CONFIG_DIR/$CONFIG.json" ]]; then
        rm -f "$BOS_CONFIG_DIR/$CONFIG.json"
        die "Error! Config '$CONFIG' does not exist!"
    fi

    set +e
    edit_file "$BOS_CONFIG_DIR/$CONFIG.json"
    if [[ "$?" == 0 ]]; then
        echo -n "Updating '$CONFIG' with new data..."
        verbose_cmd cray bos sessiontemplate create --name $CONFIG --file "$BOS_CONFIG_DIR/$CONFIG.json" --format json > /dev/null 2>&1
        echo 'done'
    else
        echo "No modifications made. Not pushing changes up"
    fi
}

function bos_boot {
    local ACTION="$1"
    local TEMPLATE="$2"
    local TARGET="$3"

    local KUBE_JOB_ID SPLIT BOS_SESSION POD LOGFILE

    cluster_defaults_config
    SPLIT=( $(echo $TARGET | sed 's/,/ /g') )
    for node in "${SPLIT[@]}"; do
        cray cfs components update --error-count 0 "$node" > /dev/null 2>&1
        cray cfs components update --enabled true "$node" > /dev/null 2>&1
    done

    if [[ -z "$TEMPLATE" || -z "$TARGET" ]]; then
        echo "USAGE: $0 bos $ACTION [template] [target nodes or groups]" 1>&2
        exit 1
    fi
    bos_exit_if_not_valid "$TEMPLATE"
    KUBE_JOB_ID=$(cray bos session create --operation "$ACTION" --template-uuid "$TEMPLATE" --limit "$TARGET"  --format json | jq '.links' | jq '.[].jobId' | grep -v null | sed 's/"//g')
    if [[ -z "$KUBE_JOB_ID" ]]; then
        die "Failed to create bos session"
    fi
    BOS_SESSION=$(echo "$KUBE_JOB_ID" | sed 's/^boa-//g')



    # if booting more than one node,
    if [[ "${#TARGET}" -ge 20 ]]; then
        LOGFILE="$BOOT_LOGS/$ACTION-$TEMPLATE.log"
    else
        LOGFILE="$BOOT_LOGS/$ACTION-$TARGET.log"
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
