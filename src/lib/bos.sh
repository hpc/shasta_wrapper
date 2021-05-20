
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
    echo -e "\tshow [template] : show details of session template"
 
    exit 1
}

function bos_list {
    refresh_cluster_groups
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
        echo "Error! $SRC is not a valid bos sessiontemplate."
        exit 2
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
    bos_exit_if_not_valid "$SRC"
    bos_exit_if_exists "$DEST"

    set -e
    tmpdir
    TMPFILE="$TMPDIR/bos_sessiontemplate.json"
    
    cray bos sessiontemplate describe $SRC --format json > "$TMPFILE" 

    cray bos sessiontemplate create --name $DEST --file "$TMPFILE" --format json
}

function bos_edit {
    local CONFIG="$1"

    bos_exit_if_not_valid "$CONFIG"

    set -e
    local CONFIG_DIR="/root/templates/"
    cray bos sessiontemplate describe $CONFIG --format json > "$CONFIG_DIR/$CONFIG.json" 

    if [[ ! -s "$CONFIG_DIR/$CONFIG.json" ]]; then
        echo "Error! Config '$CONFIG' does not exist!"
        rm -f "$CONFIG_DIR/$CONFIG.json"
        exit 2
    fi

    set +e
    edit_file "$CONFIG_DIR/$CONFIG.json"
    if [[ "$?" == 0 ]]; then
        echo -n "Updating '$CONFIG' with new data..."
        verbose_cmd cray bos sessiontemplate create --name $CONFIG --file "$CONFIG_DIR/$CONFIG.json" --format json > /dev/null 2>&1
        echo 'done'
    else
        echo "No modifications made. Not pushing changes up"
    fi
}
