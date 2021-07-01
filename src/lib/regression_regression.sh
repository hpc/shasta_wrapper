
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

