
function regression_syntax_cfs {
    echo "## cfs"
    function_ok cfs_list
    function_ok cfs_describe
    function_ok cfs_delete
    function_ok cfs_exit_if_not_valid
    function_ok cfs_exit_if_exists
    function_ok cfs_clone
    function_ok cfs_edit
    function_ok cfs_apply
    function_ok cfs_unconfigured
    function_ok read_git_config
    function_ok cfs_update
    function_ok cfs_update_git

    echo
}

function regression_cfs {
    echo "## cfs"
    ok "read_git_config returns ok" read_git_config
    ok "cfs_list returns ok" cfs_list
    ok_stdout "cfs_list has output" "cos-" cfs_list

    RANDOM_CFS_CONFIG=$(cray cfs configurations list --format json | jq '.[].name' | sed 's/"//g' | head -n 1)
    ok_stdout "cfs_describe can see random config" "\S" cfs_describe "$RANDOM_CFS_CONFIG"
    ok "cfs_exit_if_not_valid returns ok" cfs_exit_if_not_valid "$RANDOM_CFS_CONFIG"
    ok "cfs_exit_if_exists is happy with invalid" cfs_exit_if_exists asdfasdf

    ok "cfs_clone returns ok" cfs_clone "$RANDOM_CFS_CONFIG" "regression_test"
    ok "cfs_clone new clone exists" cfs_describe "regression_test"
    ok "cfs_delete returns ok" cfs_delete "regression_test"
    not_ok "cfs_clone new clone is gone now" cfs_describe "regression_test"

    echo
}
