
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function regression_syntax_bos {
    echo "## bos"
    function_ok bos
    function_ok bos_help
    function_ok refresh_bos_raw
    function_ok bos_get_default_node_group
    function_ok bos_list
    function_ok bos_describe
    function_ok bos_delete
    function_ok bos_exit_if_not_valid
    function_ok bos_exit_if_exists
    function_ok bos_clone
    function_ok bos_update_template
    function_ok bos_edit
    function_ok bos_action

    echo
}

function regression_bos {
    echo "## bos.sh"
    ok "refresh_bos_raw returns ok" refresh_bos_raw
    ok "bos_list returns ok" bos_list
    ok_stdout "bos list sees cos template" "cos-" bos_list
    RANDOM_TEMPLATE="${BOS_TEMPLATES[0]}"
    ok "bos_describe returns ok" bos_describe $RANDOM_TEMPLATE
    not_ok "bos_describe non existant template" bos_describe 00202020
    ok "bos_clone returns ok" bos_clone "$RANDOM_TEMPLATE" "regression_test"
    ok "bos_describe regression template" bos_describe "regression_test"
    ok "bos_delete regression template" bos_delete "regression_test"
    not_ok "bos_describe removed template" bos_describe "regression_test"

    echo
}
