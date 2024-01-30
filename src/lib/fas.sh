## fas library
# Contains all commands for `shasta fas`
# Used for managing firmware.

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.


FAS_SCRIPTS="$SHASTACMD_LIBDIR/../fas_scripts/"
FAS_SCRIPTS_FLASH="$FAS_SCRIPTS/flash"
FAS_SCRIPTS_CHECK="$FAS_SCRIPTS/check"
mkdir -p "$FAS_SCRIPTS"
mkdir -p "$FAS_SCRIPTS_FLASH"
mkdir -p "$FAS_SCRIPTS_CHECK"

function fas {
    case "$1" in
        check)
            shift
            fas_check_firmware "$@"
            ;;
        list)
            shift
            fas_list "$@"
            ;;
        flash)
            shift
            fas_flash_firmware "$@"
            ;;
        *)
            fas_help
            ;;
    esac
}

function fas_help {
    echo    "USAGE: $0 fas [action]"
    echo    "DESC: fas manages the validation and flashing of firmware to components"
    echo    "ACTIONS:"
    echo -e "\tcheck [component type] <node or chassis list> : check if component needs new firmware."
    echo -e "\tflash [component type] <node or chassis list> : flash firmware of the given components. Note that only components that have a differing firmware version from what is to be flashed will be updated."
    echo -e "\tlist : show shasta components can be checked and flashed"

    exit 1
}

function fas_convert2bmc {
    convert2xname "$@"
    local NODES=($RETURN )
    local NODE BMC
    RETURN=""
    for NODE in "${NODES[@]}"; do
        BMC=$(echo $NODE | sed 's/n[0-9]$//g')
        RETURN="$RETURN $BMC"
    done
    RETURN=$(echo $RETURN | sed 's/ /\n/g' | sort -u)
}

function fas_convert2chassis {
    local CHASSISES=( $@ )
    local CHASSIS
    RETURN=""
    for CHASSIS in "${CHASSISES[@]}"; do
        echo $CHASSIS | grep -Pq '^x\d+c\d+b0$'
        if [[ $? -eq 0 ]]; then
            RETURN="$RETURN $CHASSIS"
            continue
        fi
        echo $CHASSIS | grep -Pq '^x\d+c\d+$'
        if [[ $? -eq 0 ]]; then
            RETURN="$RETURN ${CHASSIS}b0"
            continue
        fi
        die "Invalid Chassis: $CHASSIS"
    done
    RETURN=$(echo $RETURN | sed 's/ /\n/g' | sort -u)
}

function fas_make_fasfile {
    local SRC_FILE="$1"
    shift
    local FAS_COMPONENT="$1"
    shift
    local COMPONENTS=( "$@" )
    local SRC_FILE DST_FILE TARGET TARGETS=()

    local TARGETS=( )
    if [[ "$FAS_COMPONENT" = Chassis* ]]; then
        fas_convert2chassis "${COMPONENTS[@]}"
        TARGETS=( $RETURN ) 
    else
        fas_convert2bmc "${COMPONENTS[@]}"
        TARGETS=( $RETURN )
    fi

    TARGET_STRING=''
    for TARGET in "${TARGETS[@]}"; do
        if [[ -z "$TARGET_STRING" ]]; then
            TARGET_STRING="$TARGET_STRING$TARGET"
        else
            TARGET_STRING="$TARGET_STRING\", \"$TARGET"
        fi
    done

    tmpdir
    DST_FILE="$RETURN/${FAS_COMPONENT}.json"

    jq ". += {\"stateComponentFilter\": { \"xnames\": [\"$TARGET_STRING\"]}}" "$SRC_FILE" > "$DST_FILE"
    
    echo "$DST_FILE"
}

## fas_check_firmware
# Look to see if given component(s) have firmware updates
function fas_check_firmware {
    local FAS_COMPONENT=$1
    shift
    local COMPONENTS=$@
    local FAS_FILE="$FAS_SCRIPTS_CHECK/${FAS_COMPONENT}.json"

    if [[ -z "$FAS_COMPONENT" ]]; then
        echo "USAGE: $0 fas check [component type] <node or component list>"
        exit 2
    fi
    setup_craycli

    if [[ -n "${COMPONENTS[@]}" ]]; then
        FAS_FILE=$(fas_make_fasfile "$FAS_FILE" "$FAS_COMPONENT" "${COMPONENTS[@]}")
    fi

    if [[ ! -f "$FAS_FILE" ]]; then
        die "Error component '$FAS_COMPONENT' no check action found!"
    fi

    grep 'overrideDryrun' "$FAS_FILE" | grep -q 'false'
    if [[ $? -ne 0 ]]; then
        echo "This is not a check run. aborting"
        exit 1
    fi

    set -e
    ACTION_ID=$(cray fas actions create "$FAS_FILE" --format json | jq -r '.actionID')
    if [[ $? -ne 0 ]]; then
        die "fas failed"
    fi

    echo -n "Querying Components"
    set +e
    RET=1
    while [[ "$RET" -ne 0 ]]; do
        echo -n .
        cray fas actions status list "$ACTION_ID" | grep -q completed
        RET=$?
        sleep 1
    done

    cray fas actions describe "$ACTION_ID" | egrep 'fromFirmwareVersion|xname|stateHelper|operationSummary*operationKeys'
    echo
    cray fas actions status list "$ACTION_ID" | grep -v '= 0'
}

## fas_check_firmware
# flash the given component(s) that have firmware updates
function fas_flash_firmware {
    local FAS_COMPONENT="$1"
    local FAS_FILE="$FAS_SCRIPTS_FLASH/${FAS_COMPONENT}.json"

    if [[ -z "$FAS_COMPONENT" ]]; then
        echo "USAGE: $0 fas flash [component type] <node or chassis list>"
        exit 2
    fi

    if [[ ! -f "$FAS_FILE" ]]; then
        die "Error component '$FAS_COMPONENT' no flash action found!"
    fi
    setup_craycli

    echo "!!!!!! WARNING !!!!!!"
    echo "If you will be flashing multiple things, be sure to flash them in the below precidence order!"
    echo "https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/Update_Firmware_with_FAS.md#hardware-precedence-order"
    echo
    echo "!!!!!! WARNING !!!!!!"
    echo "Be sure to check and follow any actions perscribed by cray in this page before flashing the node!"
    echo "https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/FAS_Use_Cases.md"
    echo
    echo -n "Are you sure you want to flash your components? [Ny]"
    read ANS

    if [[ "$ANS" != 'y' ]]; then
        exit 0
    fi

    grep -i 'overrideDryrun' "$FAS_FILE" | grep -iq 'true'
    if [[ $? -ne 0 ]]; then
        echo "This is not a flash run. aborting"
        exit 1
    fi
    if [[ -n "${COMPONENTS[@]}" ]]; then
        FAS_FILE=$(fas_make_fasfile "$FAS_FILE" "$FAS_COMPONENT" "${COMPONENTS[@]}")
    fi


    set -e
    ACTION_ID=$(cray fas actions create "$FAS_FILE" --format json | jq -r '.actionID')
    if [[ $? -ne 0 ]]; then
        die "fas failed"
    fi

    echo
    set +e
    RET=1
    while [[ "$RET" -ne 0 ]]; do
        cray fas actions status list "$ACTION_ID" | grep -q completed
        RET=$?
        echo -n .
        sleep 10
        cray fas actions status list "$ACTION_ID" | grep -v '= 0'
    done

    cray fas actions describe "$ACTION_ID" | egrep 'fromFirmwareVersion|xname|stateHelper|operationSummary*operationKeys'
    echo
    cray fas actions status list "$ACTION_ID" | grep -v '= 0'
}

## fas_list
# lists the available components
function fas_list {
    echo "=== Available FAS Actions ==="
    echo "# Check Component Types #"
    local CHECK_FILES=$(ls $FAS_SCRIPTS_CHECK | grep '\.json$' | sed 's/.json$//g')
    if [[ -n "$CHECK_FILES" ]]; then
        echo "$CHECK_FILES"
    else
        echo "Error! No check files found in $FAS_SCRIPTS_CHECK!"
        echo "Get them from https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/FAS_Use_Cases.md#update-chassis-management-module-firmware"
    fi
    echo
    echo "# Flash Component Types #"
    local FLASH_FILES=$(ls $FAS_SCRIPTS_FLASH | grep '\.json$' | sed 's/.json$//g')
    if [[ -n "$FLASH_FILES" ]]; then
        echo "$FLASH_FILES"
    else
        echo "Error! No flash files found in $FAS_SCRIPTS_FLASH!"
        echo "Get them from https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/FAS_Use_Cases.md#update-chassis-management-module-firmware"
    fi
}

