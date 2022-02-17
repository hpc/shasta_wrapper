TMPDIR=""

COLOR_RED=$(echo '\033[0;31m')
COLOR_BOLD=$(tput bold)
COLOR_RESET=$(tput sgr0)
NODE_CONVERSION_FILE=/usr/share/shasta_wrapper/node_conversion.sh
declare -A CONVERT2XNAME
declare -A CONVERT2NID
declare -A CONVERT2FULLNID
declare -A CONVERT2NMN


function die {
    echo -e "${COLOR_RED}$@${COLOR_RESET}" 1>&2
    exit 2
}

function tmpdir {
    if [[ -z "$TMPDIR" ]]; then
        TMPDIR=$(mktemp -d)
    fi
    RETURN="$TMPDIR"
}

function prompt_yn {
    local QUESTION=$1
    shift

    local ANS="0"
    while [[ "$ANS" != 'y' && "$ANS" != 'n' ]]; do
        echo "$QUESTION"
        echo -n "ANSWER [yn]: "
        read ANS
    done
    if [[ "$ANS" == 'y' ]]; then
        return 0
    else
        return 1
    fi
}

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

function verbose_cmd {
    echo
    echo
    echo "# $@"
    eval "$@"
    return $?
}

function edit_file {
    local FILE AFTER BEFORE
    local FILE="$1"

    flock -w 4 -n -x $FILE -c "$0 _edit_file $FILE" || die "Failed to get lock on $FILE. Someone else is modifying it"
}

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
        return 1
    fi
    return 0
}

function get_node_conversions {
    if [[ ! -f "$NODE_CONVERSION_FILE" ]]; then
        refresh_sat_data
    fi
    if [[ -z "${!CONVERT2XNAME[@]}" ]]; then
        source "$NODE_CONVERSION_FILE"
    fi
}

function refresh_sat_data {
    local SAT_FILE=/usr/share/shasta_wrapper/sat.out

    sat status 2> /dev/null | grep Node | sed 's/[^a-zA-Z0-9 ]//g' > "$SAT_FILE"

    IFS=$'\n'
    NODES=( $(cat "$SAT_FILE" | awk '{print $1 " " $3}') )
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

function convert2xname {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    get_node_conversions
    NODE_LIST=()

    for NODE in "${NODES[@]}"; do
        if [[ -n "${CONVERT2XNAME[$NODE]}" ]]; then
            NODE_LIST+=("${CONVERT2XNAME[$NODE]}")
        else
            die "Error node '$NODE' is invalid!"
        fi
    done
    RETURN="${NODE_LIST[*]}"
}

function convert2nid {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    refresh_sat_data
    NODE_LIST=()

    for NODE in "${NODES[@]}"; do
        if [[ -n "${CONVERT2NID[$NODE]}" ]]; then
            NODE_LIST+=("${CONVERT2NID[$NODE]}")
        else
            die "Error node '$NODE' is invalid!"
        fi
    done
    RETURN="${NODE_LIST[*]}"
}

function convert2fullnid {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    refresh_sat_data
    NODE_LIST=()


    for NODE in "${NODES[@]}"; do
        if [[ -n "${CONVERT2FULLNID[$NODE]}" ]]; then
            NODE_LIST+=("${CONVERT2FULLNID[$NODE]}")
        else
            die "Error node '$NODE' is invalid!"
        fi
    done
    RETURN="${NODE_LIST[*]}"
}

function convert2nmn {
    local NODES=( $(nodeset -e "$@") )
    local NODE
    refresh_sat_data
    NODE_LIST=()


    for NODE in "${NODES[@]}"; do
        if [[ -n "${CONVERT2NMN[$NODE]}" ]]; then
            NODE_LIST+=("${CONVERT2NMN[$NODE]}")
        else
            die "Error node '$NODE' is invalid!"
        fi
    done
    RETURN="${NODE_LIST[*]}"
}

function json_set_field {
    local FILE="$1"
    local FIELD="$2"
    local VALUE="$3"

    jq "$FIELD = \"$VALUE\"" "$FILE" > "$FILE.tmp" || return 1
    mv "$FILE.tmp" "$FILE"
    cat $FILE | jq "$FIELD" > /dev/null || return 1
    return 0
}
