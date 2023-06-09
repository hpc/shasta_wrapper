## Bos Job library
# Contains all commands for `shasta bos job`
# This includes all bos job actions. Each bos job is an action that bos attempts to perform such as rebooting or confuguring a node. Largely used for rebooting nodes, often via the group or node libraries.

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.


BOS_JOBS=( )
BOS_JOBS_RAW=""

function bos_job {
    case "$1" in
        des*)
            shift
            bos_job_describe "$@"
            ;;
        delete)
            shift
            bos_job_delete "$@"
            ;;
        li*)
            shift
            bos_job_list "$@"
            ;;
        log*)
            shift
            bos_job_log "$@"
            ;;
        sh*)
            shift
            bos_job_describe "$@"
            ;;
        *)
            bos_job_help
            ;;
    esac
}

function bos_job_help {
    echo    "USAGE: $0 bos job [action]"
    echo    "DESC: control jobs launched by bos"
    echo    "ACTIONS:"
    echo -e "\tdelete <--all|--complete> [job] : delete all, completed or specified bos jobs"
    echo -e "\tdescribe [job] : (same as show)"
    echo -e "\tlist <-s> : list bos jobs"
    echo -e "\tshow [job] : shows all info on a given bos"

    exit 1
}

## refresh_bos_jobs
# Refresh current job info from bos
function refresh_bos_jobs {
    local BOS_JOBS_RAW
    if [[ -n "${BOS_JOBS[0]}" && "$1" != "--force" ]]; then
        return
    fi
    local RET=1
    BOS_JOBS_RAW=$(rest_api_query "bos/v1/session")
    if [[ -z "$BOS_JOBS_RAW" || $? -ne 0 ]]; then	
       error "Error retrieving bos data: $BOS_JOBS_RAW"
       return 1
    fi
    BOS_JOBS=( $(echo "$BOS_JOBS_RAW" |\
        jq -r '.[]' ) )
}

## bos_job_list
# List out the bos jobs. This gets the list of all bos jobs, then gets information on them one at a time, so this can be very expensive. Thus the -s option is also prodived to just get the list of bos job ids as it's just one query.
function bos_job_list {
    local JOB
    refresh_bos_jobs
    if [[ "$1" == '-s' ]]; then
        for JOB in "${BOS_JOBS[@]}"; do
            echo "$JOB"
        done
    elif [[ -z "$1" ]]; then
        printf "${COLOR_BOLD}%28s   %37s   %30s   %10s$COLOR_RESET\n" Started ID Template Complete
        for JOB in "${BOS_JOBS[@]}"; do
            local RET=1
            while [[ "$RET" -ne 0 ]]; do
                printf "%28s   %37s   %30s   %10s\n" \
                  `rest_api_query "bos/v1/session/$JOB" 2> /dev/null \
                  | jq ". | \"\\(.start_time)   $JOB   \\(.templateName)   \\(.complete)\"" \
                  | sed 's/"//g'`
                RET=$?
            done
        done | sort
    else
	echo "Usage: $0 bos job list <options>"
	echo "Options:"
	echo -e "\t-s: short listing (just list ids). This is much faster but less informative"
    fi
}

## bos_job_describe
# describe the bos job
function bos_job_describe {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 bos job show [jobid]"
	return 1
    fi
    OUTPUT=$(rest_api_query "bos/v1/session/$1")
    local RET="$?"

    if [[ "$RET" -ne 0 ]]; then
        echo "Bos job '$1' does not exist"
    else
        echo "$OUTPUT"
    fi
    return $RET
}

## bos_job_delete
# Delete the given bos jobs
function bos_job_delete {
    local JOBS=( "$@" )
    local job comp

    # Handle options
    if [[ "$1" == "--"* ]]; then
        if [[ "${JOBS[0]}" == "--all" ]]; then
            refresh_bos_jobs
            JOBS=( "${BOS_JOBS[@]}" )
            prompt_yn "Would you really like to delete all ${#JOBS[@]} jobs?" || exit 0
        elif [[ "${JOBS[0]}" == "--complete" ]]; then
            refresh_bos_jobs
            JOBS=( )
            ALL_JOBS=( "${BOS_JOBS[@]}" )
            for job in "${BOS_JOBS[@]}"; do
                comp=`rest_api_query "bos/v1/session/$job" | jq 'select(.complete == true) .error_count'`
                if [ "$comp" = "0" ]; then
                    JOBS+=( "$job" )
                fi
            done
            prompt_yn "Would you really like to delete all completed jobs(${#JOBS[@]})?" || exit 0
        else
            echo "Invalid argument '$1'"
            JOBS=( )
        fi
    fi

    # Display help if no options given
    if [[ -z "${JOBS[@]}" ]]; then
        echo -e "USAGE: shasta bos job delete <OPTIONS> <Job list>"
	echo -e "OPTIONS:"
	echo -e "\t--all: delete all bos jobs"
	echo -e "\t--complete: delete all complete bos jobs (Can take some time to run)"
	return 1
    fi

    # Delete the jobs
    for job in "${JOBS[@]}"; do
        if [[ -z "$job" ]]; then
            continue
        fi
        echo cray bos session delete $job --format json
        rest_api_delete "bos/v1/session/$job"
    done
}
## bos_job_exit_if_not_valid
# Exit if the given bos template isn't valid (most likely it doesn't exist)
function bos_job_exit_if_not_valid {
    bos_job_describe "$1" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "Error! $1 is not a valid bos job."
    fi
}

## bos_job_log
# Get logs from a bos job
function bos_job_log {
    JOB="$1"

    if [[ -z "$JOB" ]]; then
        echo "USAGE: $0 bos job log <bos job id>"
        exit 1
    fi
    bos_job_exit_if_not_valid "$JOB"

    KUBE_JOB_ID=$(bos_job_describe "$JOB" | jq .job | sed 's/"//g')

    if [[ -z "$KUBE_JOB_ID" ]]; then
        die "Failed to find bos job $JOB"
    fi

    cd /tmp

    cmd_wait_output "READY" kubectl get pods -l job-name=$KUBE_JOB_ID -n services
    POD=$(kubectl get pods -l job-name=$KUBE_JOB_ID -n services| tail -n 1 | awk '{print $1}')
    cmd_wait kubectl logs -n services "$POD" -c boa

    echo
    echo "################################################"
    echo "#### INFO"
    echo "################################################"
    echo "BOS SESSION:    $JOB"
    echo "KUBERNETES JOB: $KUBE_JOB_ID"
    echo "KUBERNETES POD: $POD"
    echo "################################################"
    echo "#### END INFO"
    echo "################################################"

    kubectl logs -n services "$POD" -c boa -f
}

