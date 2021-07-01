
REG_FAILURES=0
REG_FAILED_TESTS=( )
REG_TESTS_RUN=0
REG_TESTS=0

function regression {
    case "$1" in
        all*)
            shift
            regression_all "$@"
            regression_finalize
            ;;
        syntax*)
            shift
            regression_syntax "$@"
            regression_finalize
            ;;
        basic*)
            shift
            regression_basic "$@"
            regression_finalize
            ;;
        build*)
            shift
            regression_build "$@"
            regression_finalize
            ;;
        *)
            regression_help
            ;;
    esac
}

function regression_help {
    echo    "USAGE: $0 regression [action]"
    echo    "DESC: Run regression tests for this script to ensure it works correctly"
    echo    "ACTIONS:"
    echo -e "\tall: Run all regression tests"
    echo -e "\tbasic: Run basic regression tests"
    echo -e "\tbuild: Run regression tests that should pass on the build host"
    echo -e "\tsyntax: do a general syntax check, ensuring all functions are available"
}

function regression_check_deps {
    cmd_exists mktemp
}

function check_deps {
    regression_check_deps
    cmd_exists jq
    cmd_exists cray
}

function regression_syntax {
    echo "#########################################"
    echo "####### Syntax Checks"
    echo "#########################################"
    # these first as all depend on them
    regression_syntax_regression
    regression_syntax_common
    regression_syntax_cluster

    # these second as the below depends on them
    regression_syntax_bos
    regression_syntax_bos_jobs
    regression_syntax_cfs
    regression_syntax_cfs_jobs
    regression_syntax_recipe

    # last as last level of dependance
    regression_syntax_image
    regression_syntax_group
    regression_syntax_node
}

function regression_all {
    regression_basic
}

function regression_basic {
    regression_build
    regression_cluster


    echo "#########################################"
    echo "####### Secondary Functionality Checks"
    echo "#########################################"
    regression_bos
    regression_bos_jobs
    regression_cfs
    regression_cfs_jobs
    regression_recipe
    regression_image
}

function regression_build {
    regression_check_deps
    regression_syntax


    echo "#########################################"
    echo "####### Core Functionality Checks"
    echo "#########################################"
    regression_regression
    regression_common
}

function regression_tests {
    REG_TESTS=$(( $REG_TESTS + $1 ))
}

function function_ok {
    local function="$1"
    is "function: '$function' exists" "`type -t $function 2>&1`" 'function'
}

function is {
    local TEST=$1
    if [[ "$2" -eq "$3" ]]; then
        reg_pass "$TEST"
    else
        reg_fail "$TEST"
    fi
}

function ok_stdout {
    local TEST="$1"
    local OUT="$2"
    shift
    shift
    eval "$@" 2> /dev/null | grep -Pq "$OUT"
    if [[ $? -eq 0 ]]; then
        reg_pass "$TEST"
    else
        reg_fail "$TEST"
    fi
}

function ok_exists {
    local TEST="$1"
    local FILE="$2"
    shift

    if [[ -e "$FILE" ]]; then
        reg_pass "$TEST"
    else
        reg_fail "$TEST"
    fi
}

function ok {
    local TEST="$1"
    shift
    "$@" > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        reg_pass "$TEST"
    else
        reg_fail "$TEST"
    fi
}

function not_ok {
    local TEST="$1"
    shift
    "$@"  > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        reg_pass "$TEST"
    else
        reg_fail "$TEST"
    fi
}

function cmd_exists {
    ok "$1 command exists" command -v $1
}

function reg_pass {
    TEST="$1"
    echo "$TEST...ok"
    REG_TESTS_RUN=$(($REG_TESTS_RUN + 1))
}

function reg_fail {
    echo "$TEST...not ok"
    REG_FAILURES=$(( $REG_FAILURES + 1 ))
    REG_TESTS_RUN=$(($REG_TESTS_RUN + 1))
    REG_FAILED_TESTS+=( "$TEST" )
}

function regression_finalize {

    echo
    echo
    echo
    echo "#########################################"
    echo "####### Results"
    echo "#########################################"
    if [[ $REG_FAILURES -ne 0 ]]; then
        echo "$REG_FAILURES TESTS FAILED!!!!!"
    fi
    echo "TESTS RAN:    $REG_TESTS_RUN"
    echo "TESTS FAILED: $REG_FAILURES"
    
    if [[ $REG_FAILURES -ne 0 ]]; then
        echo "FAILED TESTS:"
        for TEST in "${REG_FAILED_TESTS[@]}"; do
            echo -e "\t$TEST"
        done
        exit 1
    fi
    exit 0
}
