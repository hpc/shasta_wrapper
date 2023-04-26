
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function regression_syntax_recipe {
function regression_syntax_regression {
    echo "## regression"
    function_ok regression_tests
    function_ok function_ok
    function_ok is
    function_ok ok

    echo
}

function regression_regression {
    echo "## regression.sh"
    function_ok function_ok
    is "is function" f f
    ok_stdout "ok_stdout function" 'hi' echo hi
    ok "ok function" true

    echo
}

