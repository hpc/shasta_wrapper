# Power control library

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function power {
    case "$1" in
        off)
            shift
            power_action off "$@"
	    exit $?
            ;;
        on)
            shift
            power_action on "$@"
	    exit $?
            ;;
        reset)
            shift
            power_action off "$@"
	    exit $?
            ;;
        status)
            shift
            power_status "$@"
	    exit $?
            ;;
        *)
            power_help
	    exit $?
            ;;
    esac
}

function power_help {
    echo    "USAGE: $0 power [action]"
    echo    "DESC: power manages the power state of components on the system"
    echo    "ACTIONS:"
    echo -e "\toff <options> [conponents] : Power off components."
    echo -e "\ton <options> [conponents] : Power on components."
    echo -e "\treset <options> [conponents] : Reset power on components."
    echo -e "\tstatus [conponents] : Check power state on components"
    exit 1
}

function power_status {
    local TARGET=( )
    if [[ -n "$NODES_CONVERTED" ]]; then
        TARGET=( "$@" )
    else
        convert2xname "$@"
        TARGET=( $RETURN )
    fi
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')

    local OUTPUT=$(cray capmc get_xname_status create --xnames "$TARGET_STRING" --format json)
    local ON=$(echo "$OUTPUT" | jq -r '.on[]' 2> /dev/null)
    local OFF=$(echo "$OUTPUT" | jq -r '.off[]' 2> /dev/null)
    local UNKNOWN=$(echo "$OUTPUT" | jq -r '.undefined[]' 2> /dev/null)
    local ERROR=$(echo "$OUTPUT" | jq -r '.err_msg' 2> /dev/null)

    if [[ -n "$ON" ]]; then
       echo -n "on: "
       nodeset -f "$ON"
       echo
    fi
    if [[ -n "$OFF" ]]; then
       echo -n "off: "
       nodeset -f "$OFF"
       echo
    fi
    if [[ -n "$UNKNOWN" ]]; then
       echo -n "unk: "
       nodeset -f "$UNKNOWN"
       echo
    fi
    if [[ -n "$ERROR" ]]; then
       echo "ERROR: $ERROR"
    fi
}

function power_reset {
    if [[ -z "$@" ]]; then
        power_action_help reset
        return 1
    fi
    prompt_yn "Are you sure you want to reset power on these nodes?" || exit 1
    power_action off -y "$@"
    RET=$?
    sleep 10
    power_action on -y "$@"
    RET2=$?
    return $(($RET|$RET2))
}

function power_action {
    local ACTION="$1"
    shift
    local ARGS OPTION TARGET_STRING
    declare -a TARGET
    local YES=0

    ARGS=" --continue true"
    OPTIND=1
    while getopts "yfr" OPTION ; do
        case "$OPTION" in
            y) YES=1 ;;
            f) ARGS+=" --force true" ;;
            r) ARGS+=" --recursive true" ;;
            :) echo "-$OPTARG must have an arument"; exit 1 ;;
            \?) power_action_help "$ACTION" "$OPTION"
                return 1
            ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "$@" ]]; then
        power_action_help $ACTION
        return 1
    fi
    if [[ -n "$NODES_CONVERTED" ]]; then
        TARGET=( "$@" )
    else
        convert2xname "$@"
        TARGET=( $RETURN )
    fi
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')
    setup_craycli

    if [[ "$YES" == 0 ]]; then
        prompt_yn "Are you sure you want to power $ACTION ${#TARGET[@]} nodes?" || exit 1
    fi

    cray capmc xname_$ACTION create $ARGS --xnames "$TARGET_STRING" --format json
    return $?
}

function power_action_help {
    local ACTION="$1"
    local OPTION="$2"
    echo "shasta power $ACTION:  Invalid option:  -$OPTION"
    echo "shasta power $ACTION <OPTIONS> [nodelist]"
    echo "OPTIONS:"
    echo -e "\t-y: yes to all options"
    echo -e "\t-f: force action to run"
    echo -e "\t-r: Act on the thing and everything it controls(recursive)"
    return 1
}
