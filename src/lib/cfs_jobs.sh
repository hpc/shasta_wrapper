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
            cfs_log_job "$@"
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
    CFS_JOBS_RAW=$(cray cfs sessions list --format json)

    if [[ -z "#CFS_JOBS_RAW" ]]; then
        die "failed to gedt cfs data"
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

    refresh_cfs_jobs_raw

    echo "$CFS_JOBS_RAW" | jq ".[] | select(.name == \"$ID\")"
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
        verbose_cmd cray cfs sessions delete --format json $job
    done
}
