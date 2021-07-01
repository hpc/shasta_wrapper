
function regression_syntax_bos_jobs {
    echo "## bos_jobs"
    function_ok refresh_bos_jobs
    function_ok refresh_bos_jobs_raw
    function_ok bos_job_list
    function_ok bos_job_describe
    function_ok bos_job_delete
    function_ok bos_job_log

    echo
}

function regression_bos_jobs {
    echo '## bos_jobs'
    ok "refresh_bos_jobs returns ok" refresh_bos_jobs
    ok "refresh_bos_jobs_raw returns ok" refresh_bos_jobs_raw
    ok "bos_job_list returns ok" bos_job_list

    echo 
}
