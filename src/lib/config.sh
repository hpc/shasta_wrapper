#!/bin/bash


function config {
    case $1 in
        ap*)
            shift
            config_apply "$@"
            ;;
        cl*)
            shift
            config_clone "$@"
            ;;
        des*)
            shift
            config_describe "$@"
            ;;
        ed*)
            shift
            config_edit "$@"
            ;;
        delete)
            shift
            config_delete "$@"
            ;;
        li*)
            shift
            config_list "$@"
            ;;
        sh*)
            shift
            config_describe "$@"
            ;;
        *)
            config_help
            ;;
    esac
}

function config_help {
    echo    "USAGE: $0 config [action]"
    echo    "DESC: Each config is s declaration of the git ansible repos to checkout and run against each image groups defined in the bos templates. A config is defined in a bos sessiontemplate to be used to configure a node group at boot or an image after creation. Direct access via cray commands can be done via 'cray cfs configurations'"
    echo    "ACTIONS:"
    echo -e "\tapply [config] [other options] : Runs the given config against it's confgured nodes"
    echo -e "\tclone [src] [dest] : Clone an existing config"
    echo -e "\tedit [config] : Edit a given config."
    echo -e "\tdelete [config] : delete the config"
    echo -e "\tdescribe [config] : (same as show)"
    echo -e "\tlist : list all ansible configurations"
    echo -e "\tshow [config] : shows all info on a given config"

    exit 1
}


function config_list {
    cray cfs configurations list --format json | jq '.[].name' | sed 's/"//g'
}

function config_describe {
    cray cfs configurations describe "$1"
}

function config_delete {
    cray cfs configurations delete "$1"
}

function config_exit_if_not_valid {
    set +e
    cray cfs configurations describe "$1" > /dev/null 2> /dev/null
    if [[ $? -ne 0 ]]; then
        echo "Error! $SRC is not a valid configuration."
        exit 2
    fi
}

function config_exit_if_exists {
    set +e
    cray cfs configurations describe "$1" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "'$1' already exists. If you really want to overwrite it, you need to delete it first"
        exit 1
    fi
}

function config_clone {
    local SRC="$1"
    local DEST="$2"
    local TEMPFILE

    if [[ -z "$SRC" || -z "$DEST" ]]; then
        echo "USAGE: $0 config clone [src config] [dest config]" 1>&2
        exit 2
    fi
    config_exit_if_not_valid "$SRC"
    config_exit_if_exists "$DEST"

    set -e
    tmpdir
    TMPFILE="$TMPDIR/cfs_config.json"

    cray cfs configurations describe $SRC --format json --format json | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$TMPFILE"

    cray cfs configurations update $DEST --file "$TMPFILE" --format json > /dev/null 2>&1
}

function config_edit {
    local CONFIG="$1"
    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 config edit [config]" 1>&2
        exit 2
    fi

    config_exit_if_not_valid "$CONFIG"
    set -e

    local CONFIG_DIR="/root/templates/cfs_configurations/"
    cray cfs configurations describe $CONFIG --format json | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$CONFIG_DIR/$CONFIG.json" 2> /dev/null

    if [[ ! -s "$CONFIG_DIR/$CONFIG.json" ]]; then
        echo "Error! Config '$CONFIG' does not exist!"
        #rm -f "$CONFIG_DIR/$CONFIG.json"
        exit 2
    fi



    set +e
    edit_file "$CONFIG_DIR/$CONFIG.json"
    if [[ "$?" == 0 ]]; then
        echo -n "Updating '$CONFIG' with new data..."
        verbose_cmd cray cfs configurations update $CONFIG --file ""$CONFIG_DIR/$CONFIG.json"" --format json > /dev/null 2>&1
        echo 'done'
    else
        echo "No modifications made. Not pushing changes up"
    fi
}

function config_apply {

    local CONFIG=$1
    shift
    local NAME=cfs`date +%s`
    local JOB POD TRIED MAX_TRIES RET

    if [[ -z "$CONFIG" ]]; then
        echo "usage: $0 config apply <configuration name> <cray cfs sessions create args>"
        echo "cray cfs sessions create args(note --name and --configuration-name are defined for you):"
        cray cfs sessions create --help
        exit 1
    fi


    cray cfs sessions create --name "$NAME" --configuration-name $CONFIG "$@"
    sleep 1
    JOB=$(cray cfs sessions describe "$NAME" | grep job | awk '{print $3}' | sed 's/"//g')
    POD=$(kubectl describe job -n services $JOB | grep 'Created pod:' | awk '{print $7}')

    set +e
    set +x

    echo "Waiting for ansible worker pod to launch..."
    MAX_TRIES=20
    TRIED=0
    RET=1
    while [[ $RET -ne 0 ]]; do
        sleep 2
        kubectl logs -n services $POD inventory -f > /dev/null 2>&1
        RET=$?
        if [[ $TRIED -ge $MAX_TRIES ]]; then
            echo "Failed to get logging data for 'kubectl logs -n services $POD'"
            exit 1
        fi
        TRIED=$(( $TRIED + 1 ))
    done
    sleep 2
    set -e
    set -x


    kubectl logs -n services $POD inventory -f
    kubectl logs -n services $POD ansible-0 -f
    kubectl logs -n services $POD ansible-1 -f
    kubectl logs -n services $POD ansible-2 -f
    kubectl logs -n services $POD ansible-3 -f
    kubectl logs -n services $POD ansible-4 -f

}
