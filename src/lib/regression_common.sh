
function regression_syntax_common {
    echo "## common"
    function_ok die
    function_ok tmpdir
    function_ok prompt
    function_ok cmd_wait
    function_ok cmd_wait_output
    function_ok verbose_cmd
    function_ok edit_file
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
