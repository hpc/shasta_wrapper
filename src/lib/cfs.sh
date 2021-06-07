#!/bin/bash


function cfs {
    case "$1" in
        ap*)
            shift
            cfs_apply "$@"
            ;;
        cl*)
            shift
            cfs_clone "$@"
            ;;
        des*)
            shift
            cfs_describe "$@"
            ;;
        ed*)
            shift
            cfs_edit "$@"
            ;;
        delete)
            shift
            cfs_delete "$@"
            ;;
        li*)
            shift
            cfs_list "$@"
            ;;
        sh*)
            shift
            cfs_describe "$@"
            ;;
        *)
            cfs_help
            ;;
    esac
}

function cfs_help {
    echo    "USAGE: $0 cfs [action]"
    echo    "DESC: Each cfs config is a declaration of the git ansible repos to checkout and run against each image groups defined in the bos templates. A cfs is defined in a bos sessiontemplate to be used to configure a node group at boot or an image after creation. Direct access via cray commands can be done via 'cray cfs configurations'"
    echo    "ACTIONS:"
    echo -e "\tapply [cfs] [node] : Runs the given cfs against it's confgured nodes"
    echo -e "\tclone [src] [dest] : Clone an existing cfs"
    echo -e "\tedit [cfs] : Edit a given cfs."
    echo -e "\tdelete [cfs] : delete the cfs"
    echo -e "\tdescribe [cfs] : (same as show)"
    echo -e "\tlist : list all ansible configurations"
    echo -e "\tshow [cfs] : shows all info on a given cfs"

    exit 1
}


function cfs_list {
    local CONFIG CONFIGS group
    cluster_defaults_config
    echo "NAME(default cfs for)"
    CONFIGS=( $(cray cfs configurations list --format json | jq '.[].name' | sed 's/"//g'))
    for CONFIG in "${CONFIGS[@]}"; do
        echo -n "$CONFIG"
        for group in "${!CUR_IMAGE_CONFIG[@]}"; do
            if [[ "${CUR_IMAGE_CONFIG[$group]}" == "$CONFIG" ]]; then
                echo -n "$COLOR_BOLD($group)$COLOR_RESET"
            fi
        done
        echo
    done
}

function cfs_describe {
    cray cfs configurations describe "$1"
}

function cfs_delete {
    cray cfs configurations delete "$1"
}

function cfs_exit_if_not_valid {
    set +e
    cray cfs configurations describe "$1" > /dev/null 2> /dev/null
    if [[ $? -ne 0 ]]; then
        die "Error! $SRC is not a valid configuration."
    fi
}

function cfs_exit_if_exists {
    set +e
    cray cfs configurations describe "$1" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "'$1' already exists. If you really want to overwrite it, you need to delete it first"
        exit 1
    fi
}

function cfs_clone {
    local SRC="$1"
    local DEST="$2"
    local TEMPFILE

    if [[ -z "$SRC" || -z "$DEST" ]]; then
        echo "USAGE: $0 cfs clone [src cfs] [dest cfs]" 1>&2
        exit 1
    fi
    cfs_exit_if_not_valid "$SRC"
    cfs_exit_if_exists "$DEST"

    set -e
    tmpdir
    TMPFILE="$TMPDIR/cfs_config.json"

    cray cfs configurations describe $SRC --format json --format json | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$TMPFILE"

    cray cfs configurations update $DEST --file "$TMPFILE" --format json > /dev/null 2>&1
}

function cfs_edit {
    local CONFIG="$1"
    local CONFIG_DIR
    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 cfs edit [cfs]" 1>&2
        exit 1
    fi

    cfs_exit_if_not_valid "$CONFIG"
    set -e

    local CONFIG_DIR="/root/templates/cfs_configurations/"
    cray cfs configurations describe $CONFIG --format json | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$CONFIG_DIR/$CONFIG.json" 2> /dev/null

    if [[ ! -s "$CONFIG_DIR/$CONFIG.json" ]]; then
        rm -f "$CONFIG_DIR/$CONFIG.json"
        die "Error! Config '$CONFIG' does not exist!"
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

function cfs_apply {

    local CONFIG=$1
    local NODES=$2
    shift
    local NAME=cfs`date +%s`
    local JOB POD TRIED MAX_TRIES RET

    if [[ -z "$CONFIG" ]]; then
        echo "usage: $0 cfs apply [configuration name] [nodes|groups]"
        echo "cray cfs sessions create args(note --name and --cfsuration-name are defined for you):"
        cray cfs sessions create --help
        exit 1
    fi


    cray cfs sessions create --name "$NAME" --configuration-name $CONFIG --ansible-limit "$NODES"
    sleep 1
    JOB=$(cray cfs sessions describe "$NAME" | grep job | awk '{print $3}' | sed 's/"//g')
    POD=$(kubectl describe job -n services $JOB | grep 'Created pod:' | awk '{print $7}')

    set +e
    set +x

    echo "Waiting for ansible worker pod to launch..."
    MAX_TRIES=30
    TRIED=0
    RET=1
    while [[ $RET -ne 0 ]]; do
        sleep 2
        kubectl logs -n services $POD inventory -f > /dev/null 2>&1
        RET=$?
        if [[ $TRIED -ge $MAX_TRIES ]]; then
            echo "Failed to get logging data for 'kubectl logs -n services $POD inventory'"
            exit 1
        fi
        TRIED=$(( $TRIED + 1 ))
    done
    sleep 2
    set -e
    set -x

    # kubectl get pods cfs-f2df4111-fbe4-4bc5-8c65-70f5f5e03c80-xxrg2 -n services -o json | jq '.metadata.managedFields' | jq '.[].fieldsV1."f:spec"."f:containers"' | jq 'keys' | less
    kubectl logs -n services $POD inventory -f
    kubectl logs -n services $POD ansible-0 -f
    kubectl logs -n services $POD ansible-1 -f
    kubectl logs -n services $POD ansible-2 -f
    kubectl logs -n services $POD ansible-3 -f
    kubectl logs -n services $POD ansible-4 -f

    cray cfs sessions delete "$NAME"
}
