# Power control library

function power {
    case "$1" in
        off)
            shift
            exit power_action off "$@"
            ;;
        on)
            shift
            exit power_action on "$@"
            ;;
        reset)
            shift
            exit power_action off "$@"
            ;;
        status)
            shift
            exit power_status "$@"
            ;;
        *)
            exit power_help
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
    convert2xname "$@"
    local TARGET=( $RETURN )
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')

    cray capmc get_xname_status create --xnames "$TARGET_STRING"
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
    local ARGS YES=0
    local ACTION=$1
    shift

    ARGS=" --continue true"
    OPTIND=1
    while getopts "yfr" OPTION ; do
        case "$OPTION" in
            y) YES=1; ;;
            f) ARGS+=" --force true"; shift ;;
            r) ARGS+=" --recursive true" ;;
            \?) power_action_help $ACTION
                return 1
            ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "$@" ]]; then
        power_action_help $ACTION
        return 1
    fi
    convert2xname "$@"
    local TARGET=( $RETURN )
    TARGET_STRING=$(echo "${TARGET[@]}" | sed 's/ /,/g')

    if [[ "$YES" == 0 ]]; then
        prompt_yn "Are you sure you want to power $ACTION these nodes?" || exit 1
    fi
    cray capmc xname_$ACTION create $ARGS --xnames "$xlist"
    return $?
}

function power_action_help {
    local ACTION=$1
    echo "shasta power $ACTION:  Invalid option:  -$OPTARG"
    echo "shasta power $ACTION <OPTIONS> [nodelist]"
    echo "OPTIONS:"
    echo -e "\t-y: yes to all options"
    echo -e "\t-f: force action to run"
    echo -e "\t-r: Act on the thing and everything it controls(recursive)"
    return 1
}
