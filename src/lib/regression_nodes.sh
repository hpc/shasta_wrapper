
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function regression_syntax_node {
    echo "## node"
    function_ok node
    function_ok node_help
    function_ok node_2xname
    function_ok node_2nid
    function_ok node_2fullnid
    function_ok node_list
    function_ok node_reset_db
    function_ok node_status
    function_ok node_describe
    function_ok node_config
    function_ok node_clear_errors
    function_ok node_action
    function_ok node_enable
    function_ok node_disable

    echo
}
