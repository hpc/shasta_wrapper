## cfs job library
# Contains all commands for `shasta cfs job`
# Used for managing cfs actions to configure nodes or images.

CFS_JOBS_RAW=""

function cfs_job {
    case "$1" in
        des*)
            shift
            cfs_job_describe "$@"
            ;;
        delete)
            shift
            cfs_job_delete "$@"
            ;;
        li*)
            shift
            cfs_job_list "$@"
            ;;
        log*)
            shift
            cfs_job_log "$@"
            ;;
        sh*)
            shift
            cfs_job_describe "$@"
            ;;
        *)
            cfs_job_help
            ;;
    esac
}

function cfs_job_help {
    echo    "USAGE: $0 cfs job [action]"
    echo    "DESC: control jobs launched by cfs"
    echo    "ACTIONS:"
    echo -e "\tdelete [job] : delete the cfs"
    echo -e "\tdescribe [job] : (same as show)"
    echo -e "\tlist <-l>: list all ansible configurations"
    echo -e "\tlog [job] : show logs for the given cfs job (-t to get timestamps from k8s logging)"
    echo -e "\tshow [job] : shows all info on a given cfs"

    exit 1
}

## refresh_cfs_jobs_raw
# Update our copy of the cfs job data
function refresh_cfs_jobs_raw {
    if [[ -n "$CFS_JOBS_RAW" && "$1" != "--force" ]]; then
        return
    fi
    CFS_JOBS_RAW=$(rest_api_query "cfs/v2/sessions")

    if [[ -z "${CFS_JOBS_RAW[@]}" ]]; then
        die "failed to get cfs data"
    fi
}

## cfs_job_list
# List out the cfs jobs
function cfs_job_list {
    refresh_cfs_jobs_raw

    if [[ "$1" == '-l' ]]; then
        printf "${COLOR_BOLD}%19s   %44s   %20s   %8s %s$COLOR_RESET\n" DATE ID CONFIG STATE NODES
        printf "%19s   %44s   %20s   %8s %s\n" $(echo "$CFS_JOBS_RAW" |\
            jq '.[] | "\(.status.session.startTime)   \(.name)   \(.configuration.name)   \(.status.session.status)/\(.status.session.succeeded)   \(.ansible.limit)"' |\
            sed 's/"//g' |\
            sed 's|running/none|running|g' |\
            sed 's|pending/none|pending|g' |\
            sed 's|complete/false|fail|g' |\
            sed 's|complete/true|success|g' |\
            sort)
    elif [[ -z "$1" ]]; then
        printf "${COLOR_BOLD}%19s   %44s   %20s   %8s$COLOR_RESET\n" DATE ID CONFIG STATE
        printf "%19s   %44s   %20s   %8s\n" $(echo "$CFS_JOBS_RAW" |\
            jq '.[] | "\(.status.session.startTime)   \(.name)   \(.configuration.name)   \(.status.session.status)/\(.status.session.succeeded)"' |\
            sed 's/"//g' |\
            sed 's|running/none|running|g' |\
            sed 's|pending/none|pending|g' |\
            sed 's|complete/false|failed|g' |\
            sed 's|complete/true|success|g' |\
            sort)
    else
        echo "Usage: $0 cfs job list <options>"
	echo "Options:"
	echo -e "\t-l : long listing (includes nodes being run on)"
    fi
}

## cfs_job_describe
# Show the information on the given job
function cfs_job_describe {
    local ID="$1"

    if [[ -z "$ID" ]]; then
        echo "USAGE: $0 cfs job show [job]"
        exit 1
    fi

    refresh_cfs_jobs_raw --force

    local OUTPUT=$(echo "$CFS_JOBS_RAW" | jq ".[] | select(.name == \"$ID\")")
    if [[ -z "$OUTPUT" ]]; then
        return 1
    fi
    echo "$OUTPUT"
    return 0
}

## cfsi_job_exit_if_not_valid
# exit if the given cfs config is not valid (doesn't exist)
function cfs_job_exit_if_not_valid {
    cfs_job_describe "$1" > /dev/null 2> /dev/null
    if [[ $? -ne 0 ]]; then
        die "Error! $1 is not a valid cfs job/session."
    fi
}


## cfs_job_delete
# Delete the given cfs jobs
function cfs_job_delete {
    local JOBS=( "$@" )
    local job

    if [[ -z "$JOBS" ]]; then
        echo    "USAGE: $0 cfs job delete <options> [jobids]"
        echo    "OPTIONS:"
        echo -e "\t--all : delete all jobs"
        echo -e "\t--complete : delete all complete jobs"
        exit 1
    fi

    if [[ "${JOBS[0]}" == "--all" ]]; then
        refresh_cfs_jobs_raw
        JOBS=( $(echo "$CFS_JOBS_RAW" | jq '.[].name' | sed 's/"//g') )
        prompt_yn "Would you really like to delete all ${#JOBS[@]} jobs?" || exit 0

        echo
    elif [[ "${JOBS[0]}" == "--complete" ]]; then
        refresh_cfs_jobs_raw
        JOBS=( $(echo "$CFS_JOBS_RAW" | jq '.[] | select(.status.session.status == "complete")' | jq '.name' | sed 's/"//g') )
        prompt_yn "Would you really like to delete the ${#JOBS[@]} complete jobs?" || exit 0
    fi

    for job in "${JOBS[@]}"; do
        if [[ -z "$job" ]]; then
            continue
        fi
        echo cray cfs sessions delete --format json $job
        rest_api_delete "cfs/v2/sessions/$job"
    done
}

## cfs_job_log
# Get the logs from the given cfs job id
function cfs_job_log {
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
    cfs_job_exit_if_not_valid "$CFS"
    setup_craycli

    set -e
    cmd_wait_output 'job' cray cfs sessions describe "$CFS" --format json
    JOB=$(cray cfs sessions describe "$CFS" --format json | jq '.status.session.job' | sed 's/"//g')
    if [[ "$JOB" == 'null' ]]; then
        die "Error! got null kubernetes job from cfs. This can indicate an internal failure inside of cfs."
    fi

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
    cfs_job_logwatch "$POD"
}

## cfs_job_logwatch
# Get the logs of a given cfs kube pod
function cfs_job_logwatch {
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
