## cfs library
# Contains all commands for `shasta cfs`
# Used for managing what configurations to apply to images/nodes.

declare -A CFS_BRANCH CFS_URL CFS_BRANCH_DEFAULT
CONFIG_DIR="/root/templates/cfs_configurations/"
GIT_USER=""
GIT_PASSWD=""
mkdir -p $CONFIG_DIR

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
        job*)
            shift
            cfs_job "$@"
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
        update*)
            shift
            cfs_update "$@"
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
    echo -e "\tapply [cfs] [node] : Runs the given cfs against its confgured nodes"
    echo -e "\tclone [src] [dest] : Clone an existing cfs"
    echo -e "\tedit [cfs config] : Edit a given cfs."
    echo -e "\tdelete [cfs config] : delete the cfs"
    echo -e "\tdescribe [cfs config] : (same as show)"
    echo -e "\tjob [action]: Manage cfs jobs"
    echo -e "\tlist : list all ansible configurations"
    echo -e "\tshow [cfs config] : shows all info on a given cfs"
    echo -e "\tunconf : List all unconfigured nodes"
    echo -e "\tupdate [cfs configs] : update the git repos for the given cfs configuration with the latest based on the branches defined in /etc/cfs_defaults.conf"

    exit 1
}

## cfs_list
# List out the given cfs job configurations
function cfs_list {
    local CONFIG CONFIGS group
    cluster_defaults_config

    # Get all config data
    CONFIGS=( $(rest_api_query "cfs/v2/configurations" | jq '.[].name' | sed 's/"//g'))
    echo "${COLOR_BOLD}NAME(default cfs for)${COLOR_RESET}"

    # Any cfs configs that are set as a default for an ansible group should 
    # have the ansible group name in paretheses and bolded.
    for CONFIG in "${CONFIGS[@]}"; do
        echo -n "$CONFIG"
        for group in "${!CUR_IMAGE_CONFIG[@]}"; do
            if [[ "${CUR_IMAGE_CONFIG[$group]}" == "$CONFIG" ]]; then
                echo -n "$COLOR_BOLD($group)$COLOR_RESET"
            fi
        done
        echo
    done | sort
}

## cfs_describe
# Show the given cfs configuration
function cfs_describe {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 cfs describe [cfs config]"
	return 1
    fi
    rest_api_query "cfs/v2/configurations/$1"
    return $?
}

## cfs_delete
# Delete the given cfs configuration
function cfs_delete {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 cfs delete [cfs config]"
	return 1
    fi
    cray cfs configurations delete --format json "$@"
    return $?
}

## cfs_exit_if_not_valid
# exit if the given cfs config is not valid (doesn't exist)
function cfs_exit_if_not_valid {
    cfs_describe "$1" > /dev/null 2> /dev/null
    if [[ $? -ne 0 ]]; then
        die "Error! $SRC is not a valid configuration."
    fi
}

## cfs_exit_if_exists
# exit if the given cfs config exists
function cfs_exit_if_exists {
    cfs_describe "$1" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "'$1' already exists. If you really want to overwrite it, you need to delete it first"
        exit 1
    fi
}

## cfs_clone
# Clones the given ffs config to the new name. Doesn't replace any existing config
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

    cfs_describe $SRC --format json | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$TMPFILE"

    cray cfs configurations update $DEST --file "$TMPFILE" --format json > /dev/null 2>&1
    set +e
}

## cfs_edit
# Edit the given cfs config with an editor
function cfs_edit {
    local CONFIG="$1"
    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 cfs edit [cfs]" 1>&2
        exit 1
    fi

    cfs_exit_if_not_valid "$CONFIG"

    (
        set -e
        flock -x 42
        cfs_describe $CONFIG | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$CONFIG_DIR/$CONFIG.json" 2> /dev/null

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
    ) 42>/tmp/lock
}

## cfs_apply
# Run the given cfs config against the given host
function cfs_apply {
    local NAME JOB POD TRIED MAX_TRIES RET NODE_STRING ARGS OPTIND
    OPTIND=1
    while getopts "n:" OPTION ; do
        case "$OPTION" in
            n) NAME="$OPTARG"
            ;;
            \?) die 1 "cfs_apply:  Invalid option:  -$OPTARG" ; return 1 ;;
        esac
    done

    shift $((OPTIND-1))
    echo "$@"
    local CONFIG=$1
    shift
    local NODES=( "$@" )
    if [[ -z "$NAME" ]]; then
        NAME=cfs`date +%s`
    fi

    NODE_STRING=$(echo "${NODES[@]}" | sed 's/ /,/g')
    if [[ -z "$CONFIG" ]]; then
        echo "USAGE: $0 cfs apply <options> [configuration name] [nodes|groups]"
        echo "OPTIONS:"
        echo -e "\t-n - specify a name to give the cfs job"
        exit 1
    fi
    refresh_ansible_groups

    cfs_clear_node_counters "${NODES[@]}"

    if [[ -n "${NODES[*]}" ]]; then
        cray cfs sessions create --name "$NAME" --configuration-name $CONFIG --ansible-limit "$NODE_STRING" --format json
    else
        cray cfs sessions create --name "$NAME" --configuration-name $CONFIG --format json
    fi
    sleep 1
    cfs_log_job "$NAME"


    cray cfs sessions delete "$NAME"
}

## cfs_clear_node_counters
# Clear the error counters on the given node and ensure it's enabled
function cfs_clear_node_counters {
    local NODES=( "$@" )
    local NODE i COUNT JOBS

    disown -a
    for NODE in "${NODES[@]}"; do
        curl -s -k -i \
        -X PATCH -d '{ "enabled": true, "errorCount": 0 }' \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        "https://api-gw-service-nmn.local/apis/cfs/v2/components/$NODE" > /dev/null 2>&1 &
    done

    i=0
    JOBS=99
    while [[ "$JOBS" -gt "0" ]]; do
        JOBS=$(jobs -r | wc -l)
        COUNT="${#NODES[@]}"
        ((i=$COUNT - $JOBS))
        echo -en "\rUpdating node state: $i/${#NODES[@]}"
        sleep 2
    done
    echo
}

## cfs_clear_node_state
# Clear the node state forcing it to rerun cfs
function cfs_clear_node_state {
    local NODES=( "$@" )
    local NODE i COUNT JOBS

    disown -a
    for NODE in "${NODES[@]}"; do
        curl -s -k -i \
        -X PATCH -d '{ "state": [], "enabled": true, "errorCount": 0 }' \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${TOKEN}" \
        "https://api-gw-service-nmn.local/apis/cfs/v2/components/$NODE" > /dev/null 2>&1 &
    done

    i=0
    JOBS=99
    while [[ "$JOBS" -gt "0" ]]; do
        JOBS=$(jobs -r | wc -l)
        COUNT="${#NODES[@]}"
        ((i=$COUNT - $JOBS))
        echo -en "\rResetting node cfs state: $i/${#NODES[@]}"
        sleep 2
    done
    echo
    echo "All nodes have had their cfs state reset. This should cause new cfs jobs to spawn shortly." 
    echo "If you have had a lot of failed cfs runs you may need to restart the cfs batcher, as it backs off of launching when a lot have failed"
    echo
}

## cfs_unconfigured
# Get a list of the nodes that cfs has not configured, and the group that node is a member of
function cfs_unconfigured {
    refresh_ansible_groups
    NODES=( $(rest_api_query "cfs/v2/components" | jq '.[] | select(.configurationStatus != "configured")' | jq '.id' | sed 's/"//g') )

    echo -e "${COLOR_BOLD}XNAME\t\tGROUP$COLOR_RESET"
    for node in "${NODES[@]}"; do
        echo -e "$node\t${NODE2GROUP[$node]}"
    done
}

## cfs_log_job
# Get the logs from the given cfs job id
function cfs_log_job {
    TS=''
    if [[ "$1" == '-t' ]]; then
        shift
        TS='--timestamps'    
    fi

    local CFS="$1"
    local POD

    if [[ -z "$CFS" ]]; then
        echo "USAGE: $0 cfs job log <cfs jobid>"
        exit 1
    fi

    set -e
    cmd_wait_output 'job' rest_api_query "cfs/v2/sessions/$CFS"
    JOB=$(rest_api_query "cfs/v2/sessions/$CFS" | jq '.status.session.job' | sed 's/"//g')

    cmd_wait_output "READY" kubectl get pods -l job-name=$JOB -n services
    POD=$(kubectl get pods -l job-name=$JOB -n services| tail -n 1 | awk '{print $1}')
    set +e

    echo "################################################"
    echo "#### INFO"
    echo "################################################"
    echo "CFS SESSION:    $CFS"
    echo "KUBERNETES JOB: $JOB"
    echo "KUBERNETES POD: $POD"
    echo "################################################"
    echo "#### END INFO"
    echo "################################################"
    cfs_logwatch "$POD"
}

## cfs_logwatch
# Get the logs of a given cfs kube pod
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
    # TODO: This method has an issue where logs will only be shown if the init 
    # containers are successfull. Need to look at this.
    for cont in "${INIT_CONTAIN[@]}"; do
        echo
        echo
        echo "#################################################"
        echo "### init container: $cont"
        echo "#################################################"
        cmd_wait_output "Cloning successful" kubectl logs $TS -n services "$POD_ID" -c "$cont" 2>&1
        verbose_cmd kubectl logs $TS -n services -f "$POD_ID" -c $cont 2>&1
    done

    # container logs
    # We look and inventory first as it's run before and ansible ones, and is 
    # alphabetically after in the list
    echo
    echo
    echo "#################################################"
    echo "### container: inventory"
    echo "#################################################"
    cmd_wait kubectl logs $TS -n services "$POD_ID" -c "inventory" 2>&1
    verbose_cmd kubectl logs $TS -n services -f "$POD_ID" -c "inventory"
    for cont in "${CONTAIN[@]}"; do
        if [[ "$cont" != "inventory" ]]; then
            echo
            echo
            echo "#################################################"
            echo "### container: $cont"
            echo "#################################################"
            verbose_cmd kubectl logs $TS -n services -f "$POD_ID" -c $cont 2>&1

        fi
    done
}

## read_git_config
# Reads /etc/cfs_defaults.conf to get what git repos we can update with new conig ids
function read_git_config {
    local REPO

    source /etc/cfs_defaults.conf

    for REPO in "${!CFS_URL[@]}"; do
        if [[ -z "${CFS_BRANCH[$REPO]}" ]]; then
            die "$REPO is not defined for 'CFS_BRANCH'"
        fi
        CFS_BRANCH_DEFAULT["${CFS_URL[$REPO]}"]="${CFS_BRANCH[$REPO]}"
    done
    for REPO in "${!CFS_BRANCH[@]}"; do
        if [[ -z "${CFS_URL[$REPO]}" ]]; then
            die "$REPO is not defined for 'CFS_URL'"
        fi
    done
}

## cfs_update
# Update the commit ids for the given cfs configurations based on what urls and branches are defined in /etc/cfs_defaults.conf. Asks user before making any changes.
function cfs_update {
    local CONFIGS=( "$@" )
    local LAYER LAYER_URL FLOCK CONFIG

    if [[ -z "${CONFIGS[@]}" ]]; then
        prompt_yn "No arguments given, update all default cfs configs?" || exit 0
        cluster_defaults_config
        CONFIGS=( )
        for group in "${!CUR_IMAGE_CONFIG[@]}"; do
             CONFIGS+=( "${CUR_IMAGE_CONFIG[$group]}" )
        done
    fi

    for CONFIG in "${CONFIGS[@]}"; do
        local FILE="$CONFIG_DIR/$CONFIG.json"
        if [[ -z "$CONFIG" ]]; then
            echo "USAGE: $0 cfs edit [cfs]" 1>&2
            exit 1
        fi
	echo "#### $CONFIG"

        cfs_exit_if_not_valid "$CONFIG"

        read_git_config
        (
            set -e
            flock -x 42

            cfs_describe $CONFIG | jq 'del(.name)' | jq 'del(.lastUpdated)' > "$FILE" 2> /dev/null

            if [[ ! -s "$FILE" ]]; then
                rm -f "$FILE"
                die "Error! Config '$CONFIG' does not exist!"
            fi
            tmpdir

            GIT_REPO_COUNT=$(cat "$FILE" | jq '.layers[].commit' | wc -l)
            GIT_REPO_COUNT=$(($GIT_REPO_COUNT - 1))
            for LAYER in $(seq 0 $GIT_REPO_COUNT); do
                cfs_update_git "$FILE" "$LAYER" "$CONFIG"
            done
            rmdir "$TMPDIR" > /dev/null 2>&1
            set +e
        ) 42>/tmp/lock

	echo
	echo
    done
}

## get_git_password
# Pull the git password out of kubernetes
function get_git_password {
    if [[ -n "$GIT_PASSWD" ]]; then
        return
    fi
    GIT_USER=crayvcs
    GIT_PASSWD=$(kubectl get secret -n services vcs-user-credentials --template={{.data.vcs_password}} | base64 --decode)
    if [[ -z "$GIT_PASSWD" ]]; then
        die "Failed to get git password"
    fi
}

## cfs_update_git
# Given the cfs configuration, update it's commit ids with the commit ids of the beanch specified in /etc/cfs_defaults.conf.
function cfs_update_git {
    local FILE="$1"
    local LAYER="$2"
    local CONFIG="$3"


    get_git_password

    set -e
    LAYER_URL=$(cat "$FILE" | jq ".layers[$LAYER].cloneUrl" | sed 's/"//g')
    if [[ -n "${CFS_BRANCH_DEFAULT[$LAYER_URL]}" ]]; then
        LAYER_CUR_COMMIT=$(cat "$FILE" | jq ".layers[$LAYER].commit" | sed 's/"//g')
        URL=$(echo "$LAYER_URL" | sed "s|https://|https://$GIT_USER:$GIT_PASSWD@|g"| sed "s|http://|http://$GIT_USER:$GIT_PASSWD@|g")

        echo "cloning $LAYER_URL"
        cd "$TMPDIR"
        git clone "$URL" "$TMPDIR/$LAYER"
        cd "$TMPDIR/$LAYER"
        git checkout "${CFS_BRANCH_DEFAULT[$LAYER_URL]}"

        NEW_COMMIT=$(git rev-parse HEAD)
        if [[ "$LAYER_CUR_COMMIT" != "$NEW_COMMIT" ]]; then
            echo "old commit: $LAYER_CUR_COMMIT"
            echo "new commit: $NEW_COMMIT"
            prompt_yn "Would you like to apply the new commit '$NEW_COMMIT' for '$LAYER_URL'?" || return 0
            json_set_field "$FILE" ".layers[$LAYER].commit" "$NEW_COMMIT"
            verbose_cmd cray cfs configurations update $CONFIG --file "$CONFIG_DIR/$CONFIG.json" --format json > /dev/null 2>&1
        else
            echo "No updates. commit: '$NEW_COMMIT', old commit: '$LAYER_CUR_COMMIT'"
        fi
    else
        echo "$LAYER_URL is not defined in /etc/cfs_defaults.conf... skipping"
    fi
    rm -rf "$TMPDIR/$LAYER"
    set +e
}
