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
        unconf*)
            shift
            cfs_unconfigured "$@"
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
    echo -e "\tunconf : List all unconfigured nodes"

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
    shift
    local NODES=( "$@" )
    local NAME=cfs`date +%s`
    local JOB POD TRIED MAX_TRIES RET NODE_STRING ARGS

    if [[ -z "$CONFIG" ]]; then
        echo "usage: $0 cfs apply [configuration name] [nodes|groups]"
        echo "cray cfs sessions create args(note --name and --cfsuration-name are defined for you):"
        cray cfs sessions create --help
        exit 1
    fi

    SPLIT=( $(echo $NODES | sed 's/,/ /g') )
    for node in "${SPLIT[@]}"; do
        cray cfs components update --error-count 0 "$node" > /dev/null 2>&1
        cray cfs components update --enabled true "$node" > /dev/null 2>&1
    done

    ARGS=""
    if [[ -n "${NODES[0]}" ]]; then
        NODE_STRING=$(echo "${NODES[@]}" | sed 's/ /,/g')
        ARGS="--ansible-limit '$NODES'"
    fi
    cray cfs sessions create --name "$NAME" --configuration-name $CONFIG $ARGS
    sleep 1
    JOB=$(cray cfs sessions describe "$NAME" | grep job | awk '{print $3}' | sed 's/"//g')
    POD=$(kubectl describe job -n services $JOB | grep 'Created pod:' | awk '{print $7}')

    set +e
    set +x

    echo "Waiting for ansible worker pod to launch..."

    cfs_logwatch "$POD"

    cray cfs sessions delete "$NAME"
}

function cfs_unconfigured {
    refresh_ansible_groups
    NODES=( $(cray cfs components list --format json | jq '.[] | select(.configurationStatus != "configured")' | jq '.id' | sed 's/"//g') )

    echo -e "${COLOR_BOLD}XNAME\t\tGROUP$COLOR_RESET"
    for node in "${NODES[@]}"; do
        echo -e "$node\t${NODE2GROUP[$node]}"
    done
}

function cfs_logwatch {
    POD_ID=$1
    INIT_CONTAIN=( $(kubectl get pods "$POD_ID" -n services -o json |\
        jq '.metadata.managedFields' |\
        jq '.[].fieldsV1."f:spec"."f:initContainers"' |\
        grep -v null |\
        jq 'keys' |\
        grep name |\
        sed 's|  "k:{\\"name\\":\\"||g' |\
        sed 's|\\"}"||g' | \
        sed 's/,//g') )

    CONTAIN=( $(kubectl get pods $POD_ID -n services -o json |\
        jq '.metadata.managedFields' |\
        jq '.[].fieldsV1."f:spec"."f:containers"' |\
        grep -v null |\
        jq 'keys' |\
        grep name |\
        sed 's|  "k:{\\"name\\":\\"||g' |\
        sed 's|\\"}"||g' | \
        sed 's/,//g') )

    # init container logs
    cmd_wait kubectl logs -n services "$POD_ID" -c "${INIT_CONTAIN[0]}"

    for cont in "${INIT_CONTAIN[@]}"; do
        echo
        echo
        echo "#################################################"
        echo "### init container: $cont"
        echo "#################################################"
        verbose_cmd kubectl logs -n services -f "$POD_ID" -c $cont 2>&1
    done

    # container logs
    echo
    echo
    echo "#################################################"
    echo "### container: inventory"
    echo "#################################################"
    cmd_wait kubectl logs -n services "$POD_ID" -c "inventory"
    verbose_cmd kubectl logs -n services -f "$POD_ID" -c "inventory"
    for cont in "${CONTAIN[@]}"; do
        if [[ "$cont" != "inventory" ]]; then
            echo
            echo
            echo "#################################################"
            echo "### container: $cont"
            echo "#################################################"
            verbose_cmd kubectl logs -n services -f "$POD_ID" -c $cont 2>&1 |\
                grep -v '^Waiting for the previous configuration layer to complete$'
        fi
    done
}
