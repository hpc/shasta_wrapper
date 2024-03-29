## common library
# Contains common functions used in the shasta wrapper

# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

declare -A BOS_DEFAULT CONFIG_DEFAULT RECIPE_DEFAULT IMAGE_DEFAULT IMAGE_DEFAULT_NAME CUR_IMAGE_ID CUR_IMAGE_NAME CUR_IMAGE_ETAG IMAGE_GROUPS CONFIG_IMAGE_DEFAULT
CLUSTER_GROUPS=( )

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
    error "$@"
    exit 2
}

## error
# Print the string to stderr and red
function error {
    echo -e "${COLOR_RED}$@${COLOR_RESET}" 1>&2
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


## wait_for_background_tasks
# Wait for all background tasks to complete
function wait_for_background_tasks {
    local MESSAGE="$1"
    local TOTAL="$2"
    local COUNT JOBS

    i=0
    JOBS=99
    while [[ "$JOBS" -gt "0" ]]; do
        JOBS=$(jobs -r | wc -l)
        ((COUNT=$TOTAL - $JOBS))
        echo -en "\r$MESSAGE: $COUNT/$TOTAL"
        sleep 2
    done
    echo
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
    get_kube_token

    local RAW=$(curl -w '\nhttp_code: %{http_code}\n' -s -k -H "$CRAY_AUTH_HEADER" "https://api-gw-service-nmn.local/apis/$API")
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
    get_kube_token

    local RAW=$(curl -X DELETE -w '\nhttp_code: %{http_code}\n' -s -k -H "$CRAY_AUTH_HEADER" "https://api-gw-service-nmn.local/apis/$API")
    local OUTPUT=$(echo "$RAW" | head -n -1)
    local HTTP_CODE=$(echo "$RAW" | tail -n 1 | sed 's/http_code: //g')
    echo "$OUTPUT"
    echo $HTTP_CODE | grep -Eq '200|204'
    return $?
}

## rest_api_patch
# Send a query request to the api server
function rest_api_patch {
    local API="$1"
    local DATA="$2"
    get_kube_token

    local RAW=$(curl -w '\nhttp_code: %{http_code}\n' \
      -s -k \
      -H "$CRAY_AUTH_HEADER" \
      -X PATCH \
      -d "$DATA" \
      -H "Content-Type: application/json" \
      "https://api-gw-service-nmn.local/apis/$API"
    )
    local OUTPUT=$(echo "$RAW" | head -n -1)
    local HTTP_CODE=$(echo "$RAW" | tail -n 1 | sed 's/http_code: //g')
    echo "$OUTPUT"
    echo $HTTP_CODE | grep -q 200
    return $?
}

## get_node_conversions
# Setup node conversions for all different node names and types (ie xname to nid) if it hasn't been done already.
function get_node_conversions {
    hsm_get_node_state
    if [[ ! -f "$NODE_CONVERSION_FILE" ]]; then
        refresh_sat_data
    fi
    if [[ -z "${!CONVERT2FULLNID[@]}" ]]; then
        source "$NODE_CONVERSION_FILE"
    fi
}

## refresh_sat_data
# Pull down all the data from sat and use it to build a table of all conversion information (is nid to xname)
function refresh_sat_data {
    local XNAME NID FULLNID NMN NODES ADD_ZEROS I
    hsm_get_node_state

    echo "#!/bin/bash" > "$NODE_CONVERSION_FILE"

    for XNAME in "${!HSM_NODE_ENABLED[@]}"; do
        NID="${CONVERT2NID[$XNAME]}"
        if [[ -z "$NID" ]]; then
            continue
        fi
        FULLNID="$NID"
        if [[ "${#NID}" -lt 6 ]]; then
            ADD_ZEROS=$(( 6 - "${#NID}" ))
            I=0
            while [[ "$I" -lt $ADD_ZEROS ]]; do
                FULLNID="0$FULLNID"
                (( I++ ))
            done
        fi
        FULLNID="nid$FULLNID"
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
    source "$NODE_CONVERSION_FILE"
}

## add_node_name
# attempt to add a new node to the lookup tables
function add_node_name {
    local NAME="$1"
    local XNAME NID FULLNID NMN
    get_node_conversions

    # Try to figure out it's xname
    IPS=$(getent hosts $NODE | awk '{print $1}')
    if [[ -z "$IPS" ]]; then
        die "Error node '$NODE' is invalid!"
    fi
    for IP in $IPS; do
        XNAME=$(nslookup "$IP" | awk '{print $4}' | sed 's/\.$//g' |grep  -P '^x\d+c\d+s\d+.*' | head -n 1)
        if [[ -n "$XNAME" ]]; then
            break
	fi
    done
    if [[  -z "$XNAME" ]]; then
        die "Error node '$NODE' is invalid!"
    fi

    # If this is a real node (added recently for example) it will show up in the
    # CONVERT2NID but not in the CONVERT2FULLNID. This is because we refresh hsm
    # every query, but don't construct the fullnids as it's expensive. If this is
    # the case, we need to force the recreation of the xnames.
    if [[ -n "${CONVERT2NID[$NAME]}" && -z "${CONVERT2FULLNID[$NAME]}" ]]; then
        refresh_sat_data
        return
    fi
    if [[ -n "${CONVERT2NID[$XNAME]}" && -z "${CONVERT2FULLNID[$XNAME]}" ]]; then
        refresh_sat_data
        return
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
    if [[ -z "$@" ]]; then
        RETURN=()
        return
    fi
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
    if [[ -z "$@" ]]; then
        RETURN=()
        return
    fi
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
    if [[ -z "$@" ]]; then
        RETURN=()
        return
    fi
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
    if [[ -z "$@" ]]; then
        RETURN=()
        return
    fi
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

## cluster_defaults_config
# Grab all the defaults for each node group and set their variables
function cluster_defaults_config {
    local IMAGE_RAW BOS
    if [[ -n "${!BOS_DEFAULT[@]}" ]]; then
        return 0
    fi
    source /etc/shasta_wrapper/cluster_defaults.conf
    refresh_bos_raw
    for group in "${!BOS_DEFAULT[@]}"; do
        BOS=$(echo "$BOS_RAW" | jq ".[] | select(.name == \"${BOS_DEFAULT[$group]}\")")

        if [[ -z "$BOS" && -n "$BOS_RAW" ]]; then
            echo "Error: default BOS_DEFAULT '${BOS_DEFAULT[$group]}' set for group '$group' is not a valid  bos sessiontemplate. Check /etc/shasta_wrapper/cluster_defaults.conf" 1>&2
	    continue
        fi

	if [[ -z "${CONFIG_DEFAULT[$group]}" ]]; then
            CONFIG_DEFAULT[$group]=$(echo "$BOS" | jq '.cfs.configuration' | sed 's/"//g')
	fi
	if [[ -z "${CONFIG_IMAGE_DEFAULT[$group]}" ]]; then
            CONFIG_IMAGE_DEFAULT[$group]="${CONFIG_DEFAULT[$group]}"
	fi
        CUR_IMAGE_ETAG[$group]=$(echo "$BOS" | jq '.boot_sets[].etag' | sed 's/"//g')
    done
}

# Go through and check all the configuration and validate it all looks sane (check that things actually map to things that exist)
function cluster_validate {
    local group RECIPE CONFIG
    declare -a GROUP_LIST
    cluster_defaults_config

    local CONFIG_RAW CONFIG RECIPE_RAW RECIPE
    CONFIG_RAW=$(rest_api_query "cfs/v2/configurations")
    RECIPE_RAW=$(rest_api_query "ims/recipes")
    GROUP_LIST=( $(echo "${!BOS_DEFAULT[@]}" "${!IMAGE_DEFAULT[@]}" | sed 's/ /\n/g' | sort -u) )
    for group in "${GROUP_LIST[@]}"; do
        echo -n "Checking $group..."
        # Validate recipe used exists
        if [[ -z "${IMAGE_DEFAULT[$group]}" ]]; then
            RECIPE=$(echo "$RECIPE_RAW" | jq ".[] | select(.id == \"${RECIPE_DEFAULT[$group]}\")")
            if [[ -z "$RECIPE" ]]; then
                echo
                die "Error config '${RECIPE_DEFAULT[$group]}' set for group '$group' is not a valid recipe. Check config defaults /etc/shasta_wrapper/cluster_defaults.conf."
            fi
        fi
        # Validate cfs configuration used exists
        CONFIG=$(echo "$CONFIG_RAW" | jq ".[] | select(.name == \"${CONFIG_DEFAULT[$group]}\")")
        if [[ -z "$CONFIG" ]]; then
            echo
            die "Error config '${CONFIG_DEFAULT[$group]}' set in bos sessiontemplate '${BOS_DEFAULT[$group]}' is not a valid configuration. check bos configuration."
        fi
        # Validate cfs configuration used exists
        CONFIG_IMAGE=$(echo "$CONFIG_RAW" | jq ".[] | select(.name == \"${CONFIG_IMAGE_DEFAULT[$group]}\")")
        if [[ -z "$CONFIG" ]]; then
            echo
            die "Error image config '${CONFIG_IMAGE_DEFAULT[$group]}' is not a valid configuration. check cluster_defaults"
        fi
        echo "ok"
    done
}

function get_kube_token {
    if [[ -n "$CRAY_ACCESS_TOKEN_RAW" && -n "$CRAY_AUTH_HEADER" ]]; then
        return
    fi
    local CLIENT_SECRET ACCESS_TOKEN

    CLIENT_SECRET=$(kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}' | base64 -d)
    if [[ -z "$CLIENT_SECRET" ]]; then
	echo "Failed to get client secret from admin-client-auth kubernetes secret" >2
	die "See 'kubectl get secrets admin-client-auth -o jsonpath='{.data.client-secret}'"
    fi

    export CRAY_ACCESS_TOKEN_RAW=$(curl -s -d grant_type=client_credentials -d client_id=admin-client -d client_secret=$CLIENT_SECRET \
	https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token)

    if [[ -z "$CRAY_ACCESS_TOKEN_RAW" ]]; then
	echo "Failed to get access token!"
	die "See 'curl -s -d grant_type=client_credentials -d client_id=admin-client -d client_secret=$CLIENT_SECRET https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token'"
    fi

    ACCESS_TOKEN=$(echo "$CRAY_ACCESS_TOKEN_RAW" | jq -r .access_token)

    if [[ -z "$ACCESS_TOKEN"  ]]; then
        die "Failed to get access token from raw output. Likely invalid output from: 'curl -s -d grant_type=client_credentials -d client_id=admin-client -d client_secret=$CLIENT_SECRET https://api-gw-service-nmn.local/keycloak/realms/shasta/protocol/openid-connect/token'"
    fi
    export CRAY_AUTH_HEADER="Authorization: Bearer $ACCESS_TOKEN"

}

function setup_craycli {
    get_kube_token
    local CRAY_CLI_TOKEN_DIR="$HOME/.config/cray"
    local CRAY_CLI_TOKEN_FILE="$CRAY_CLI_TOKEN_DIR/tokens"
    if [[ ! -f "$CRAY_CLI_TOKEN_FILE" ]]; then
        return
    fi

    echo "$CRAY_ACCESS_TOKEN_RAW" > $CRAY_CLI_TOKEN_FILE
}
