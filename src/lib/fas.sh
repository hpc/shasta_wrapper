## fas library
# Contains all commands for `shasta fas`
# Used for managing firmware.


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
    echo -e "\tcheck [conponent] : check if component needs new firmware."
    echo -e "\tflash [conponent] : flash firmware of the given components. Note that only components that have a differing firmware version from what is to be flashed will be updated."
    echo -e "\tlist : show shasta components can be checked and flashed"

    exit 1
}

## fas_check_firmware
# Look to see if given component(s) have firmware updates
function fas_check_firmware {
    local FAS_COMPONENT=$1
    local FAS_FILE="$FAS_SCRIPTS_CHECK/${FAS_COMPONENT}.json"

    if [[ -z "$FAS_COMPONENT" ]]; then
        echo "USAGE: $0 fas check [component]"
        exit 2
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
    local FAS_COMPONENT=$1
    local FAS_FILE="$FAS_SCRIPTS_FLASH/${FAS_COMPONENT}.json"

    if [[ -z "$FAS_COMPONENT" ]]; then
        echo "USAGE: $0 fas flash [component]"
        exit 2
    fi

    if [[ ! -f "$FAS_FILE" ]]; then
        die "Error component '$FAS_COMPONENT' no flash action found!"
    fi

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

    set -e
    ACTION_ID=$(cray fas actions create "$FAS_FILE" --format json | jq -r '.actionID')

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
    echo "# Check Component Options #"
    local CHECK_FILES=$(ls $FAS_SCRIPTS_CHECK | grep '\.json$' | sed 's/.json$//g')
    if [[ -n "$CHECK_FILES" ]]; then
        echo "$CHECK_FILES"
    else
        echo "Error! No check files found in $FAS_SCRIPTS_CHECK!"
        echo "Get them from https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/FAS_Use_Cases.md#update-chassis-management-module-firmware"
    fi
    echo
    echo "# Flash Component Options #"
    local FLASH_FILES=$(ls $FAS_SCRIPTS_FLASH | grep '\.json$' | sed 's/.json$//g')
    if [[ -n "$FLASH_FILES" ]]; then
        echo "$FLASH_FILES"
    else
        echo "Error! No flash files found in $FAS_SCRIPTS_FLASH!"
        echo "Get them from https://github.com/Cray-HPE/docs-csm/blob/main/operations/firmware/FAS_Use_Cases.md#update-chassis-management-module-firmware"
    fi
}
