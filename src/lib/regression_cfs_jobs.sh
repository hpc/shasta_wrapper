
function regression_syntax_cfs_jobs {
    echo "## cfs_jobs"
    function_ok cfs_job
    function_ok cfs_job_help
    function_ok refresh_cfs_jobs_raw
    function_ok cfs_job_list
    function_ok cfs_job_describe
    function_ok cfs_job_delete
}

function regression_cfs_jobs {
    echo "## cfs_jobs"
    ok "cfs_job returns ok" cfs_job
    ok "refresh_cfs_jobs_raw returns ok" refresh_cfs_jobs_raw
    ok "cfs_job_list returns ok" cfs_job_list
}
