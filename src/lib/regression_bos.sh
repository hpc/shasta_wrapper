
function regression_syntax_bos {
    echo "## bos"
    function_ok bos 
    function_ok bos_help 
    function_ok refresh_bos_raw 
    function_ok bos_list 
    function_ok bos_describe 
    function_ok bos_delete 
    function_ok bos_exit_if_not_valid 
    function_ok bos_exit_if_exists 
    function_ok bos_clone 
    function_ok bos_update_template 
    function_ok bos_edit 
    function_ok bos_boot
}

function regression_bos {
    echo "## bos.sh"
    ok "bos returns ok" bos
    ok "refresh_bos_raw returns ok" refresh_bos_raw
    ok "bos_list returns ok" bos_list
    ok_stdout "bos list sees cos template" "cos-" bos_list
}

