## common library
# Contains common functions used in the shasta wrapper

TMPDIR=""

COLOR_RED=$(echo '\033[0;31m')
COLOR_BOLD=$(tput bold)
COLOR_RESET=$(tput sgr0)
NODE_CONVERSION_FILE=/usr/share/shasta_wrapper/node_conversion.sh
declare -A CONVERT2XNAME
declare -A CONVERT2NID
declare -A CONVERT2FULLNID
declare -A CONVERT2NMN

## die
# exit with return code 2 and pring the error in red
function die {
    echo -e "${COLOR_RED}$@${COLOR_RESET}" 1>&2
    exit 2
}

## tmpdir
# make a demporary directory and report it's location in the RETURN variable
function tmpdir {
    if [[ -z "$TMPDIR" ]]; then
        TMPDIR=$(mktemp -d)
    fi
    RETURN="$TMPDIR"
}

## prompt_yn
# Prompt the user to answer a yes/no question. If ASSUME_YES is set, it will auto assume yes ignoring prompting the user.
function prompt_yn {
    local QUESTION=$1
    shift

    local ANS="0"
    echo "$QUESTION"
    if [[ -n "$ASSUME_YES" ]]; then
        echo "ANSWER [yn]: ASSUMING YES"
        return 0
    fi
    while [[ "$ANS" != 'y' && "$ANS" != 'n' ]]; do
        echo -n "ANSWER [yn]: "
        read ANS
    done
    if [[ "$ANS" == 'y' ]]; then
        return 0
    else
        return 1
    fi
}


## prompt
# Prompt the user with a multiple choice question
function prompt {
    local QUESTION=$1
    shift
    local ANSWERS=( "$@" )

    local ANS="${#ANSWERS[@]}"
    while [[ "$ANS" -ge "${#ANSWERS[@]}" ]]; do
        echo "$QUESTION"
        local I=0
        for item in "${ANSWERS[@]}"; do
            echo "$I: ${ANSWERS[$I]}"
            (( I++ ))
        done
        echo -n "ANSWER: "
        read ANS
    done
    return $ANS
}

## cmd_wait
# Wait for the given command to return 0
function cmd_wait {
    local RET=1
    set +e
    echo "Waiting for zero return code on '$@'"
    while [[ $RET -ne 0 ]]; do
        echo -n '.'
        "$@" > /dev/null 2>&1
        RET=$?
        if [[ $RET -ne 0 ]]; then
            sleep 2
        fi
    done
}

## cmd_wait_output
# Wait for the given command to return the given output (continuiously runs the command until it gets the expected output)
function cmd_wait_output {
    local OUTPUT=$1
    shift
    RET=1
    set +e
    echo "Waiting for '$OUTPUT' from output on '$@'"
    while [[ $RET -ne 0 ]]; do
        echo -n '.'
        "$@" | egrep -q "$OUTPUT"  > /dev/null 2>&1
        RET=$?
        if [[ $RET -ne 0 ]]; then
            sleep 2
        fi
    done
    echo
}


## verbose_cmd
# Run the command and output the command that was run
function verbose_cmd {
    echo
    echo
    echo "# $@"
    eval "$@"
    return $?
}

## edit_json_file
# open the given file with the given command (blocking wait)
function check_json_file {
    local FILE AFTER BEFORE RET
    local FILE="$1"

    cat "$FILE" | jq > /dev/null
    return $?
}

## edit_file
# open the given file with the given command (blocking wait)
function edit_file {
    local FILE AFTER BEFORE RET NO_CHANGES_OK
    local FILE="$1"
    local FILE_TYPE="$2"

    RET=1
    while [[ $RET -ne 0 ]]; do
        flock -w 4 -n -x $FILE -c "$0 _edit_file $FILE"
        RET=$?
        if [[ $RET -eq 1 ]]; then
            die "Failed to get lock on $FILE. Someone else is modifying it"
        elif [[ $RET -eq 2 ]]; then
            if [[ "$NO_CHANGES_OK" -ne 1 ]]; then
                echo "No changes made, aborting!"
                exit 0
            fi
        fi
        if [[ "$FILE_TYPE" == "json" ]]; then
            check_json_file "$FILE"
            RET=$?
        else
            RET=0
        fi
        if [[ $RET -ne 0 ]]; then
            echo "Error! Syntax errors found!"
            echo "Press enter to fix file. Hit ctrl-c to discard changes to file"
            read
            NO_CHANGES_OK=1
        fi
    done
}

## edit_file_nolock
# Edit the given file without any locking wait with whatever EDITOR is set to, or use vim.
function edit_file_nolock {
    local FILE AFTER BEFORE
    local FILE="$1"

    BEFORE=$(md5sum "$FILE")
    if [[ -n "$EDITOR" ]]; then
        $EDITOR "$FILE"
    else
        vim "$FILE"
    fi
    AFTER=$(md5sum "$FILE")

    if [[ "$BEFORE" == "$AFTER" ]]; then
        return 2
    fi
    return 0
}
## refresh_node_conversions_data
# Delete and regenerate the node conversion database
function refresh_node_conversions_data {
    rm -f "$NODE_CONVERSION_FILE"
    refresh_sat_data
}

## rest_api_query
# Send a query request to the api server
function rest_api_query {
    local API="$1"
    local RAW=$(curl -w 'http_code: %{http_code}\n' -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/$API")
    local OUTPUT=$(echo "$RAW" | head -n -1)
    local HTTP_CODE=$(echo "$RAW" | tail -n 1 | sed 's/http_code: //g')
    echo "$OUTPUT"
    echo $HTTP_CODE | grep -q 200
    return $?
}

## rest_api_delete
# Send a delete request to the api server
function rest_api_delete {
    local API="$1"
    local RAW=$(curl -X DELETE -w 'http_code: %{http_code}\n' -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/$API")
    local OUTPUT=$(echo "$RAW" | head -n -1)
    local HTTP_CODE=$(echo "$RAW" | tail -n 1 | sed 's/http_code: //g')
    echo "$OUTPUT"
    echo $HTTP_CODE | grep -Eq '200|204'
    return $?
}

## get_node_conversions
# Setup node conversions for all different node names and types (ie xname to nid) if it hasn't been done already.
function get_node_conversions {
    if [[ ! -f "$NODE_CONVERSION_FILE" ]]; then
        refresh_sat_data
    fi
    if [[ -z "${!CONVERT2XNAME[@]}" ]]; then
        source "$NODE_CONVERSION_FILE"
    fi
}

## refresh_sat_data
# Pull down all the data from sat and use it to build a table of all conversion information (is nid to xname)
function refresh_sat_data {
    local XNAME NID FULLNID NMN NODES
    local SAT_FILE=/usr/share/shasta_wrapper/sat.out

    sat status --no-headings --no-borders --fields xname,nid | awk '{print $1 " " $2}' > "$SAT_FILE"

    IFS=$'\n'
    NODES=( $(cat "$SAT_FILE") )
    IFS=$' \t\n'

    echo "#!/bin/bash" > "$NODE_CONVERSION_FILE"

    for NODE in "${NODES[@]}"; do
        LINES=( $NODE )
        XNAME="${LINES[0]}"
        NID="${LINES[1]}"
        FULLNID=$(printf 'nid%06d' $NID)
        NMN="$FULLNID-nmn"

        echo  >> "$NODE_CONVERSION_FILE"
        echo  >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2XNAME[$NID]=$XNAME" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2XNAME[$FULLNID]=$XNAME" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2XNAME[$NMN]=$XNAME" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2XNAME[$XNAME]=$XNAME" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NID[$XNAME]=$NID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NID[$FULLNID]=$NID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NID[$NMN]=$NID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NID[$NID]=$NID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2FULLNID[$NMN]=$FULLNID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2FULLNID[$XNAME]=$FULLNID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2FULLNID[$NID]=$FULLNID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2FULLNID[$FULLNID]=$FULLNID" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NMN[$FULLNID]=$NMN" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NMN[$XNAME]=$NMN" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NMN[$NID]=$NMN" >> "$NODE_CONVERSION_FILE"
        echo "CONVERT2NMN[$NMN]=$NMN" >> "$NODE_CONVERSION_FILE"
    done
}

## add_node_name
# attempt to add a new node to the lookup tables
function add_node_name {
    local NAME="$1"
    local XNAME NID FULLNID NMN
    get_node_conversions

    # Try to figure out it's xname
    IP=$(getent hosts $NODE | awk '{print $1}')
    if [[ -z "$IP" ]]; then
        die "Error node '$NODE' is invalid!"
    fi
    XNAME=$(nslookup "$IP" | awk '{print $4}' | sed 's/\.$//g' |grep  -P '^x\d+c\d+s\d+.*' | head -n 1)
    if [[  -z "$XNAME" ]]; then
        die "Error node '$NODE' is invalid!"
    fi

    # Validate the xname looks valid
    if [[ -n "${CONVERT2NID[$NAME]}" ]]; then
        return # already added
    fi
    if [[ -z "${CONVERT2NID[$XNAME]}" ]]; then
        die "add_node_name: '$XNAME' is not a valid xname!"
    fi
    if [[ -z "${CONVERT2FULLNID[$XNAME]}" ]]; then
        die "add_node_name: '$XNAME' is not a valid xname!"
    fi
    if [[ -z "${CONVERT2NMN[$XNAME]}" ]]; then
        die "add_node_name: '$XNAME' is not a valid xname!"
    fi
    if [[ -z "${CONVERT2XNAME[$XNAME]}" ]]; then
        die "add_node_name: '$XNAME' is not a valid xname!"
    fi

    # Save the host for later fast lookup
    NID="${CONVERT2NID[$XNAME]}"
    FULLNID="${CONVERT2FULLNID[$XNAME]}"
    NMN="${CONVERT2NMN[$XNAME]}"
    echo >> "$NODE_CONVERSION_FILE"
    echo "CONVERT2XNAME[$NAME]=$XNAME" >> "$NODE_CONVERSION_FILE"
    echo "CONVERT2NID[$NAME]=$NID" >> "$NODE_CONVERSION_FILE"
    echo "CONVERT2FULLNID[$NAME]=$FULLNID" >> "$NODE_CONVERSION_FILE"
    echo "CONVERT2NMN[$NAME]=$NMN" >> "$NODE_CONVERSION_FILE"
    CONVERT2XNAME[$NAME]="$XNAME"
    CONVERT2NID[$NAME]="$NID"
    CONVERT2FULLNID[$NAME]="$FULLNID"
    CONVERT2NMN[$NAME]="$NMN"
}

## convert2xname
# attempt to convert the given name into it's xname
function convert2xname {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    get_node_conversions
    NODE_LIST=()

    for NODE in "${NODES[@]}"; do
        if [[ -z "${CONVERT2XNAME[$NODE]}" ]]; then
            add_node_name "$NODE"
        fi
        NODE_LIST+=("${CONVERT2XNAME[$NODE]}")
    done
    RETURN="${NODE_LIST[*]}"
}

## convert2nid
# attempt to convert the given name into it's nid
function convert2nid {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    get_node_conversions
    NODE_LIST=()

    for NODE in "${NODES[@]}"; do
        if [[ -z "${CONVERT2NID[$NODE]}" ]]; then
            add_node_name "$NODE"
        fi
        NODE_LIST+=("${CONVERT2NID[$NODE]}")
    done
    RETURN="${NODE_LIST[*]}"
}

## convert2fullnid
# attempt to convert the given name into it's fullnid
function convert2fullnid {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    get_node_conversions
    NODE_LIST=()


    for NODE in "${NODES[@]}"; do
        if [[ -z "${CONVERT2FULLNID[$NODE]}" ]]; then
            add_node_name "$NODE"
        fi
        NODE_LIST+=("${CONVERT2FULLNID[$NODE]}")
    done
    RETURN="${NODE_LIST[*]}"
}

## convert2nmn
# attempt to convert the given name into it's nmn hostname
function convert2nmn {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    get_node_conversions
    NODE_LIST=()


    for NODE in "${NODES[@]}"; do
        if [[ -z "${CONVERT2NMN[$NODE]}" ]]; then
            add_node_name "$NODE"
        fi
        NODE_LIST+=("${CONVERT2NMN[$NODE]}")
    done
    RETURN="${NODE_LIST[*]}"
}

## json_set_field
# Set the given field in a json file
function json_set_field {
    local FILE="$1"
    local FIELD="$2"
    local VALUE="$3"

    jq "$FIELD = \"$VALUE\"" "$FILE" > "$FILE.tmp" || return 1
    mv "$FILE.tmp" "$FILE"
    cat $FILE | jq "$FIELD" > /dev/null || return 1
    return 0
}
