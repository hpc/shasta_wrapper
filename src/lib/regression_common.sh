
function regression_syntax_common {
    echo "## common"
    function_ok die
    function_ok tmpdir
    function_ok prompt_yn
    function_ok prompt
    function_ok wait_for_background_tasks
    function_ok cmd_wait
    function_ok cmd_wait_output
    function_ok verbose_cmd
    function_ok check_json_file
    function_ok edit_file
    function_ok edit_file_nolock
    function_ok refresh_node_conversions_data
    function_ok rest_api_query
    function_ok rest_api_delete
    function_ok rest_api_patch
    function_ok get_node_conversions
    function_ok refresh_sat_data
    function_ok add_node_name
    function_ok convert2xname
    function_ok convert2nid
    function_ok convert2fullnid
    function_ok convert2nmn
    function_ok json_set_field

    echo
}

function regression_common {
    echo "## common"
    ok "tmpdir returns ok" tmpdir
    ok_exists "tmpdir created tmpdir" "$TMPDIR"
    ok "cmd_wait returns ok" cmd_wait sleep 2
    ok "cmd_wait_output returns ok" cmd_wait_output "hi" echo hi
    ok_stdout "verbose_cmd output ok" 'echo hi' verbose_cmd echo hi 

    echo
}
