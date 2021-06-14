
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
    echo -e "\tlist : list all ansible configurations"
    echo -e "\tlog [job] : show logs for the given cfs job"
    echo -e "\tshow [job] : shows all info on a given cfs"

    exit 1
}

function refresh_cfs_jobs_raw {
    if [[ -n "$CFS_JOBS_RAW" && "$1" != "--force" ]]; then
        return
    fi
    CFS_JOBS_RAW=$(cray cfs sessions list --format json)
}

function cfs_job_list {
    refresh_cfs_jobs_raw
    echo "${COLOR_BOLD}DATE                  ID                                             STATE$COLOR_RESET"
    echo "$CFS_JOBS_RAW" |\
        jq '.[] | "\(.status.session.startTime)   \(.name)   \(.status.session.status)"' |\
        sed 's/"//g' |\
        sort
}

function cfs_job_describe {
    local ID="$1"

    if [[ -z "$ID" ]]; then
        echo "USAGE: $0 cfs job show [job]"
        exit 1
    fi

    refresh_cfs_jobs_raw

    echo "$CFS_JOBS_RAW" | jq ".[] | select(.name == \"$ID\")"
}

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
        prompt "Would you really like to delete all ${#JOBS[@]} jobs?(WARNING this will also delete all bos jobs!)" "Yes" "No" || exit 0
        bos_job_delete --all || exit 0
    elif [[ "${JOBS[0]}" == "--complete" ]]; then
        refresh_cfs_jobs_raw
        JOBS=( $(echo "$CFS_JOBS_RAW" | jq '.[] | select(.status.session.status == "complete")' | jq '.name' | sed 's/"//g') )
        prompt "Would you really like to delete the ${#JOBS[@]} complete jobs?" "Yes" "No" || exit 0
    fi

    for job in "${JOBS[@]}"; do
        verbose_cmd cray cfs sessions delete $job
        sleep 2
    done
}