
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
    echo -e "\tdelete [job] : delete the bos"
    echo -e "\tdescribe [job] : (same as show)"
    echo -e "\tlist : list bos jobs"
    echo -e "\tshow [job] : shows all info on a given bos"

    exit 1
}

function refresh_bos_jobs {
    if [[ -n "${BOS_JOBS[0]}" && "$1" != "--force" ]]; then
        return
    fi
    BOS_JOBS=( $(cray bos session list --format json |\
        jq '.[]' |\
        sed 's/"//g') )
}

function refresh_bos_jobs_raw {
    local JOB
    if [[ -n "$BOS_JOBS_RAW" && "$1" != "--force" ]]; then
        return
    fi
    refresh_bos_jobs $1

    BOS_JOBS_RAW=$(for JOB in "${BOS_JOBS[@]}"; do
        cray bos session describe $JOB --format json
    done)
}


function bos_job_list {
    local JOB
    refresh_bos_jobs
    for JOB in "${BOS_JOBS[@]}"; do
        echo "$JOB"
    done
}

function bos_job_describe {
    cray bos session describe "$1"
}

function bos_job_delete {
    local JOBS=( "$@" )
    local job

    if [[ "${JOBS[0]}" == "--all" ]]; then
        refresh_bos_jobs
        JOBS=( $(echo "$BOS_JOBS") )
        prompt "Would you really like to delete all ${#JOBS[@]} jobs?" "Yes" "No" || exit 0
    fi

    for job in "${JOBS[@]}"; do
        verbose_cmd cray bos session delete $job
        sleep 2
    done
}
