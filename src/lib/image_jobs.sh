## image job library
# Contains all commands for `shasta image job`
# Commands for managing image build and configure jobs (note that for configuration jobs it's both a ims job and a cfs job)

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

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

## refresh_image_jobs_raw
# Get information on all ims jobs
function refresh_image_jobs_raw {
    if [[ -n "$IMS_JOBS_RAW" && "$1" != "--force" ]]; then
        return
    fi
    IMS_JOBS_RAW=$(rest_api_query "ims/jobs")
    while [[ -z "$IMS_JOBS_RAW" ]]; do
	sleep 2
        IMS_JOBS_RAW=$(rest_api_query "ims/jobs")
    done

    if [[ -z "$IMS_JOBS_RAW" ]]; then
        die "failed to get image data"
    fi
}

## image_job_list
# list all ims jobs
function image_job_list {
    refresh_image_jobs_raw
    printf "${COLOR_BOLD}%33s   %44s   %8s$COLOR_RESET\n" DATE ID STATE
    printf "%33s   %44s   %8s\n" $(echo "$IMS_JOBS_RAW" |\
        jq '.[] | "\(.created)   \(.id)   \(.status)"' |\
        sed 's/"//g' |\
        sort)
}

## image_job_describe
# Show information on the given ims job
function image_job_describe {
    local ID="$1"

    if [[ -z "$ID" ]]; then
        echo "USAGE: $0 image job show [job]"
        exit 1
    fi

    refresh_image_jobs_raw

    echo "$IMS_JOBS_RAW" | jq ".[] | select(.id == \"$ID\")"
    return $?
}

## image_job_delete
# Delete the given ims job
function image_job_delete {
    local JOBS=( "$@" )
    local job

    if [[ "$1" == '--'* ]]; then
        if [[ "${JOBS[0]}" == "--all" ]]; then
            refresh_image_jobs_raw
            JOBS=( $(echo "$IMS_JOBS_RAW" | jq '.[].id' | sed 's/"//g') )
            prompt_yn "Would you really like to delete all ${#JOBS[@]} jobs?" || exit 0

        elif [[ "${JOBS[0]}" == "--complete" ]]; then
            refresh_image_jobs_raw
            JOBS=( $(echo "$IMS_JOBS_RAW" | jq '.[] | select(.status == "success")' | jq '.id' | sed 's/"//g') )
            prompt_yn "Would you really like to delete the ${#JOBS[@]} complete jobs?" || exit 0
	else
            echo "Invalid argument: '${JOBS[0]}'"
	    JOBS=( )
        fi
    fi

    if [[ -z "$JOBS" ]]; then
        echo    "USAGE: $0 image job delete <options> [jobids]"
        echo    "OPTIONS:"
        echo -e "\t--all : delete all jobs"
        echo -e "\t--complete : delete all complete jobs"
        exit 1
    fi

    for job in "${JOBS[@]}"; do
        if [[ -z "$job" ]]; then
            continue
        fi
        echo cray ims jobs delete --format json $job
        rest_api_delete "ims/jobs/$job"
    done
}

## image_job_exit_if_not_valid
# Exit if the given image job isn't valid (most likely it doesn't exist)
function image_job_exit_if_not_valid {
    image_job_describe "$1" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "Error! $1 is not a valid image job."
    fi
}

## image_job_log
# Get logs in the given ims job
function image_job_log {
    ID="$1"

    if [[ -z "$ID" ]]; then
        echo "USAGE: $0 image job log [image job id]"
	exit 1
    fi
    image_job_exit_if_not_valid "$ID"

    cmd_wait_output "job" rest_api_query "ims/jobs/$ID"
    refresh_image_jobs_raw

    JOB_ID=$(echo "$IMS_JOBS_RAW" | jq ".[] | select(.id == \"$ID\")" | jq '.kubernetes_job' | sed 's/"//g')
    if [[ -z "$JOB_ID" ]]; then
        die "ERROR! Failed to get job id for image job '$ID'"
    fi

    image_logwatch "$JOB_ID"
}
