
function regression_syntax_cfs_jobs {
    echo "## cfs_jobs"
    function_ok refresh_cfs_jobs_raw
    function_ok cfs_job_list
    function_ok cfs_job_describe
    function_ok cfs_job_delete
    function_ok cfs_job_log
    function_ok cfs_job_logwatch

    echo
}

function regression_cfs_jobs {
    echo "## cfs_jobs"
    ok "refresh_cfs_jobs_raw returns ok" refresh_cfs_jobs_raw
    ok "cfs_job_list returns ok" cfs_job_list

   echo
}
