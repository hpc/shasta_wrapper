
BOS_CONFIG_DIR="/root/templates/"
BOOT_LOGS="/var/log/boot/"`date '+%Y%m%d-%H%M%S'`

function bos {
    case $1 in
        clo*)
            shift
            bos_clone "$@"
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
            bos_reboot "$@"
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
    echo -e "\tedit [template] : edit a bos session template"
    echo -e "\tdescribe [template] : (same as show)"
    echo -e "\tlist : show all bos session templates"
    echo -e "\treboot [template] [nodes|groups] : reboot a given node into the given bos template"
    echo -e "\tshow [template] : show details of session template"

    exit 1
}

function bos_list {
    cluster_defaults_config
    echo "NAME(Nodes applied to at boot)"
    BOS_LINES=( $(cray bos sessiontemplate list --format json | jq '.[].name' | sed 's/"//g') )

    for line in "${BOS_LINES[@]}"; do
        echo -n "$line"
        for group in "${!BOS_DEFAULT[@]}"; do
            if [[ "${BOS_DEFAULT[$group]}" == "$line" ]]; then
                 echo -n "($group)"
            fi
        done
        echo
    done
}

function bos_describe {
    cray bos sessiontemplate describe "$1"
    exit $?
}

function bos_delete {
    cray bos sessiontemplate delete "$1"
    exit $?
}

function bos_exit_if_not_valid {
    cray bos sessiontemplate describe "$1" > /dev/null 2>&1
    if [[ $! -ne 0 ]]; then
        die "Error! $SRC is not a valid bos sessiontemplate."
    fi
}

function bos_exit_if_exists {
    cray bos sessiontemplate describe "$1" > /dev/null 2>&1
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

    cray bos sessiontemplate describe $SRC --format json > "$TMPFILE"

    cray bos sessiontemplate create --name $DEST --file "$TMPFILE" --format json
}

function bos_update_template {
    local TEMPLATE="$1"
    local KEY="$2"
    local VALUE="$3"

    set -e
    cray bos sessiontemplate describe "$TEMPLATE" --format json > "$BOS_CONFIG_DIR/$TEMPLATE.json"
    json_set_field "$BOS_CONFIG_DIR/$TEMPLATE.json" "$KEY" "$VALUE"
    cray bos sessiontemplate create --name $TEMPLATE --file "$BOS_CONFIG_DIR/$TEMPLATE.json" --format json > /dev/null 2>&1
    cray bos sessiontemplate describe "$TEMPLATE" --format json > "$BOS_CONFIG_DIR/$TEMPLATE.json"
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
    cray bos sessiontemplate describe $CONFIG --format json > "$BOS_CONFIG_DIR/$CONFIG.json"

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

function bos_reboot {
    local TEMPLATE="$1"
    local TARGET="$2"

    local KUBE_JOB_ID

    cluster_defaults_config
    SPLIT=( $(echo $TARGET | sed 's/,/ /g') )
    for node in "${SPLIT[@]}"; do
        cray cfs components update --error-count 0 "$node" > /dev/null 2>&1
        cray cfs components update --enabled true "$node" > /dev/null 2>&1
    done

    if [[ -z "$TEMPLATE" || -z "$TARGET" ]]; then
        echo "USAGE: $0 bos reboot [template] [target nodes or groups]" 1>&2
        exit 1
    fi
    bos_exit_if_not_valid "$CONFIG"
    KUBE_JOB_ID=$(cray bos session create --operation reboot --template-uuid "$TEMPLATE" --limit "$TARGET"  --format json | jq '.links' | jq '.[].jobId' | grep -v null | sed 's/"//g')
    if [[ -z "$KUBE_JOB_ID" ]]; then
        die "Failed to create bos session"
    fi
    BOS_SESSION=$(echo "$KUBE_JOB_ID" | sed 's/^boa-//g')

    cmd_wait_output "Created pod:" kubectl describe job -n services "$KUBE_JOB_ID"

    POD=$(kubectl describe job -n services "$KUBE_JOB_ID" | grep 'Created pod:' | awk '{print $7}' )

    cd /tmp
    mkdir -p "$BOOT_LOGS"
    echo "reboot action initiated. details:"
    echo "BOS Session: $BOS_SESSION"
    echo "kubernetes pod: $POD"
    echo
    echo "Starting Boot..."
    echo "Boot Logs: '$BOOT_LOGS/reboot-$TARGET.log'"
    cmd_wait kubectl logs -n services "$POD" -c boa
    kubectl logs -n services "$POD" -c boa -f > "$BOOT_LOGS/reboot-$TARGET.log" 2>&1
    echo
}
