
IMS_JOBS_RAW=""

function image_job {
    case "$1" in
        des*)
            shift
            image_job_describe "$@"
            ;;
        delete)
            shift
            image_job_delete "$@"
            ;;
        li*)
            shift
            image_job_list "$@"
            ;;
        log*)
            shift
            image_job_log "$@"
            ;;
        sh*)
            shift
            image_job_describe "$@"
            ;;
        *)
            image_job_help
            ;;
    esac
}

function image_job_help {
    echo    "USAGE: $0 image job [action]"
    echo    "DESC: control jobs launched by image"
    echo    "ACTIONS:"
    echo -e "\tdelete [job] : delete the image"
    echo -e "\tdescribe [job] : (same as show)"
    echo -e "\tlist : list all ansible configurations"
    echo -e "\tlog [job] : show logs for the given image job"
    echo -e "\tshow [job] : shows all info on a given image"

    exit 1
}

function refresh_image_jobs_raw {
    if [[ -n "$IMS_JOBS_RAW" && "$1" != "--force" ]]; then
        return
    fi
    IMS_JOBS_RAW=$(cray ims jobs list --format json)
    while [[ -z "$IMS_JOBS_RAW" ]]; do
	sleep 2
        IMS_JOBS_RAW=$(cray ims jobs list --format json)
    done

    if [[ -z "$IMS_JOBS_RAW" ]]; then
        die "failed to get image data"
    fi
}

function image_job_list {
    refresh_image_jobs_raw
    printf "${COLOR_BOLD}%33s   %44s   %8s$COLOR_RESET\n" DATE ID STATE
    printf "%33s   %44s   %8s\n" $(echo "$IMS_JOBS_RAW" |\
        jq '.[] | "\(.created)   \(.id)   \(.status)"' |\
        sed 's/"//g' |\
        sort)
}

function image_job_describe {
    local ID="$1"

    if [[ -z "$ID" ]]; then
        echo "USAGE: $0 image job show [job]"
        exit 1
    fi

    refresh_image_jobs_raw

    echo "$IMS_JOBS_RAW" | jq ".[] | select(.id == \"$ID\")"
}

function image_job_delete {
    local JOBS=( "$@" )
    local job

    if [[ -z "$JOBS" ]]; then
        echo    "USAGE: $0 image job delete <options> [jobids]"
        echo    "OPTIONS:"
        echo -e "\t--all : delete all jobs"
        echo -e "\t--complete : delete all complete jobs"
        exit 1
    fi

    if [[ "${JOBS[0]}" == "--all" ]]; then
        refresh_image_jobs_raw
        JOBS=( $(echo "$IMS_JOBS_RAW" | jq '.[].id' | sed 's/"//g') )
        prompt "Would you really like to delete all ${#JOBS[@]} jobs?" "Yes" "No" || exit 0

    elif [[ "${JOBS[0]}" == "--complete" ]]; then
        refresh_image_jobs_raw
        JOBS=( $(echo "$IMS_JOBS_RAW" | jq '.[] | select(.status == "success")' | jq '.id' | sed 's/"//g') )
        prompt "Would you really like to delete the ${#JOBS[@]} complete jobs?" "Yes" "No" || exit 0
    fi

    for job in "${JOBS[@]}"; do
        verbose_cmd cray ims jobs delete $job
        sleep 2
    done
}

function image_job_log {
    ID="$1"

    cmd_wait_output "job" cray ims jobs describe "$ID"
    refresh_image_jobs_raw

    JOB_ID=$(echo "$IMS_JOBS_RAW" | jq ".[] | select(.id == \"$ID\")" | jq '.kubernetes_job' | sed 's/"//g')
    echo "JOB_ID: $JOB_ID"

    image_logwatch "$JOB_ID"
}
