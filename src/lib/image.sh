
declare -A IMAGE_ID2NAME
declare -A IMAGE_ID2CREATED

IMAGE_LOGDIR="/var/log/image/"`date '+%Y%m%d-%H%M%S'`

function image {
    case "$1" in
        bu*)
            shift
            image_build "$@"
            ;;
        co*)
            shift
            image_configure "$@"
            ;;
        li*)
            shift
            image_list "$@"
            ;;
        des*)
            shift
            image_describe "$@"
            ;;
        delete)
            shift
            image_delete "$@"
            ;;
        map)
            shift
            image_map "$@"
            ;;
        sh*)
            shift
            image_describe "$@"
            ;;
        *)
            image_help
            ;;
    esac
}

function image_help {
    echo    "USAGE: $0 image [action]"
    echo    "DESC: The images used by the system to boot nodes. To set an image to be used at boot,  See 'cray cfs configurations' for more detailed options."
    echo    "ACTIONS:"
    echo -e "\tbuild [recipe id] [group] [config] <image name>: build a new image from the given recipe"
    echo -e "\tconfigure [image id] [group name] [config name] : build a new image configuring it"
    echo -e "\tdelete [image id] : delete a image"
    echo -e "\tlist : list all images"

    exit 1
}

function refresh_images {
    local RAW image
    echo "# cray ims images list --format json | jq '.[] | \"\\(.created)   \\(.id)   \\(.name)\"' | sed 's/\"//g' | sort"

    IFS=$'\n'
    RAW=( $(cray ims images list --format json | jq '.[] | "\(.id) \(.created) \(.name)"' | sed 's/"//g') )
    IFS=$' \t\n'

    for image in "${RAW[@]}"; do
        SPLIT=( $image )
        id="${SPLIT[0]}"
        created="${SPLIT[1]}"
        name="${SPLIT[*]:2}"
        IMAGE_ID2NAME[$id]=$name
        IMAGE_ID2CREATED[$id]=$created
    done
}

function image_list {
    local id name created group
    cluster_defaults_config
    refresh_images
    echo "CREATED                            ID                                     NAME(Mapped image for)"
    for id in "${!IMAGE_ID2NAME[@]}"; do
        name="${IMAGE_ID2NAME[$id]}"
        created="${IMAGE_ID2CREATED[$id]}"
        for group in "${!CUR_IMAGE_ID[@]}"; do
            if [[ "${CUR_IMAGE_ID[$group]}" == "$id" ]]; then
                name="$name$COLOR_BOLD($group)$COLOR_RESET"
            fi
        done
        echo "$created   $id   $name"
    done | sort
}

function image_describe {
    verbose_cmd cray ims images describe "$1"
}

function image_delete {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 image delete [image1] <images...>" 1>&2
        exit 1
    fi
    for image in "$@"; do
        verbose_cmd cray ims images delete "$image" | grep -P '\S'
    done
    echo "Cleaning up image artifacts..."
    image_clean_deleted_artifacts
}

function image_build {
    local RECIPE_ID="$1"
    local GROUP_NAME="$2"
    local CONFIG_NAME=$3
    local NEW_IMAGE_NAME="$4"
    local BOS_TEMPLATE="$5"
    local EX_HOST BARE_IMAGE_ID CONFIG_IMAGE_ID


    if [[ -z "$RECIPE_ID" || -z "$GROUP_NAME" || -z "CONFIG_NAME" ]]; then
        echo "USAGE: $0 image build [recipe id] [group] [config] <image name>" "<bos template to map to>" 1>&2
        exit 1
    fi


    EX_HOST=$(grep -A 2 $GROUP_NAME /etc/ansible/hosts | grep '{}' | awk '{print $1}' | sed 's/://g')
    if [[ -z "$EX_HOST" ]]; then
        die "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
    fi

    cray cfs configurations describe "$CONFIG_NAME" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "'$CONFIG_NAME' is not a valid configuration."
    fi
    if [[ -z "$NEW_IMAGE_NAME" ]]; then
        NEW_IMAGE_NAME="img_$GROUP_NAME"
    fi
    if [[ -n "$BOS_TEMPLATE" ]]; then
        echo "[$GROUP_NAME] Image will be mapped to '$BOS_TEMPLATE' if build/configure succeed."
    fi

   # quick sleep here to help consolidate the map and build messages
   sleep 1


    mkdir -p "$IMAGE_LOGDIR"
    echo "[$GROUP_NAME] Bare image build started. Full logs at: '$IMAGE_LOGDIR/bare-${NEW_IMAGE_NAME}.log'"
    image_build_bare "$RECIPE_ID" "$NEW_IMAGE_NAME" "$GROUP_NAME" > "$IMAGE_LOGDIR/bare-${NEW_IMAGE_NAME}.log"
    if [[ $? -ne 0 ]]; then
        die "[$GROUP_NAME] bare image build failed... Not continuing"
    fi
    BARE_IMAGE_ID="$RETURN"


    echo "[$GROUP_NAME] Configure image started. Full logs at: '$IMAGE_LOGDIR/config-${NEW_IMAGE_NAME}.log'"
    image_configure "$BARE_IMAGE_ID" "$GROUP_NAME" "$CONFIG_NAME" > "$IMAGE_LOGDIR/config-${NEW_IMAGE_NAME}.log"
    if [[ $? -ne 0 ]]; then
        die "[$GROUP_NAME] configure image failed... Not continuing"
    fi
    CONFIG_IMAGE_ID="$RETURN"



    if [[ -n "$BOS_TEMPLATE" ]]; then
        image_map "$BOS_TEMPLATE" "$CONFIG_IMAGE_ID" "$GROUP_NAME"
    fi
}

function image_map {
    local BOS_TEMPLATE="$1"
    local IMAGE_ID="$2"
    local GROUP="$3"

    if [[ -z "$BOS_TEMPLATE" || -z "$IMAGE_ID" ]]; then
        echo "USAGE: $0 image map [bos template] [image id] <name>" 1>&2
        exit 1
    fi
    IMAGE_RAW=$(cray ims images list --format json | jq ".[] | select(.id == \"$IMAGE_ID\")")

    IMAGE_ETAG=$(echo "$IMAGE_RAW" | jq '.link.etag' | sed 's/"//g')
    IMAGE_PATH=$(echo "$IMAGE_RAW" | jq '.link.path' | sed 's/"//g')
    if [[ -z "$IMAGE_ETAG" ]]; then
        die "etag could not be found for image: '$IMAGE_ID'. Did you provide a valid image id?"
    fi

    bos_update_template "$BOS_TEMPLATE" ".boot_sets.compute.etag" "$IMAGE_ETAG"
    if [[ $? -ne 0 ]]; then
        die "Failed to map image id '$IMAGE_ID' to bos template '$BOS_TEMPLATE'" 1>&2
    fi
    bos_update_template "$BOS_TEMPLATE" ".boot_sets.compute.path" "$IMAGE_PATH"
    if [[ $? -ne 0 ]]; then
        die "Failed to map image id '$IMAGE_ID' to bos template '$BOS_TEMPLATE'" 1>&2
    fi
    if [[ -n "$GROUP" ]]; then
        echo "[$GROUP] Successfully mapped '$BOS_TEMPLATE' to '$IMAGE_ID'"
    else
        echo "Successfully mapped '$BOS_TEMPLATE' to '$IMAGE_ID'"
    fi
    return 0
}

function image_build_bare {
    local RECIPE_ID=$1
    local NEW_IMAGE_NAME=$2
    local GROUP_NAME=$3
    local JOB_RAW JOB_ID IMS_JOB_ID POD IMAGE_ID

    if [[ -z "$RECIPE_ID" ]]; then
        echo "[$GROUP_NAME] Error. recipe id must be provided!"
        die "[$GROUP_NAME] Error. recipe id must be provided!"
    fi
    refresh_recipes
    if [[ -n "${RECIPE_ID2NAME[$RECIPE_ID]}" ]]; then
    	local RECIPE_NAME="${RECIPE_ID2NAME[$RECIPE_ID]}"
    else
        echo "[$GROUP_NAME] Error! RECIPE ID '$RECIPE_ID' doesn't exist."
        die "[$GROUP_NAME] Error! RECIPE ID '$RECIPE_ID' doesn't exist."
    fi
    if [[ -z "$NEW_IMAGE_NAME" ]]; then
        NEW_IMAGE_NAME="img_$RECIPE_NAME"
    fi

    set -e
    echo "cray ims jobs create \
      --job-type create \
      --image-root-archive-name $NEW_IMAGE_NAME \
      --artifact-id $RECIPE_ID \
      --public-key-id $IMS_PUBLIC_KEY_ID \
      --enable-debug False \
      --format json"
    JOB_RAW=$(cray ims jobs create \
      --job-type create \
      --image-root-archive-name $NEW_IMAGE_NAME \
      --artifact-id $RECIPE_ID \
      --public-key-id $IMS_PUBLIC_KEY_ID \
      --enable-debug False \
      --format json)

    JOB_ID=$(echo "$JOB_RAW" | jq '.kubernetes_job' | sed 's/"//g')
    echo "  Grabbing kubernetes_job = '$JOB_ID' from output..."
    IMS_JOB_ID=$(echo "$JOB_RAW" | jq '.id' | sed 's/"//g')
    echo "  Grabbing id = '$IMS_JOB_ID' from output..."

    sleep 3
    cmd_wait_output "SuccessfulCreate" kubectl describe job -n ims $JOB_ID
    POD=$(kubectl describe job -n ims $JOB_ID | grep SuccessfulCreate | awk '{print $7}')
    echo "  Grabbing pod_id = '$POD' from output..."

    cmd_wait kubectl logs -n ims -f $POD -c build-ca-rpm
    sleep 1
    for log in fetch-recipe wait-for-repos build-ca-rpm build-image; do
        verbose_cmd kubectl logs -n ims -f $POD -c $log 2>&1
        sleep 2
    done

    verbose_cmd kubectl describe job -n ims $JOB_ID | grep -q 'Pods Statuses:  0 Running / 1 Succeeded'
    RET=$?
    if [[ $RET -eq 0 ]]; then
        echo "[$GROUP_NAME] IMAGE BUILD FAILED: job id '$JOB_ID'"
        die "[$GROUP_NAME] IMAGE BUILD FAILED: job id '$JOB_ID'"
    fi

    set +e
    cmd_wait_output "success|error" cray ims jobs describe $IMS_JOB_ID

    IMAGE_ID=$(cray ims jobs describe $IMS_JOB_ID | grep 'resultant_image_id' | awk '{print $3}' | sed 's/"//g' )
    echo "  Grabbing image_id = '$IMAGE_ID' from output..."

    verbose_cmd cray ims images describe "$IMAGE_ID" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] Error image build failed! See logs for details"
        die "[$GROUP_NAME] Error image build failed! See logs for details"
    fi
    echo "  Ok, image does appear to exist. Cleaning up the job..."

    verbose_cmd cray ims jobs delete $IMS_JOB_ID

    echo "[$GROUP_NAME] Bare image Created: $IMAGE_ID" 1>&2
    echo "[$GROUP_NAME] Bare image Created: $IMAGE_ID"
    RETURN="$IMAGE_ID"
    return 0
}

function image_configure {
    local IMAGE_ID=$1
    local GROUP_NAME=$2
    local CONFIG_NAME=$3
    local SESSION_NAME EX_HOST JOB_ID POD_ID NEW_IMAGE_ID

    local GROUP_SANITIZED=$(echo "$GROUP_NAME" | awk '{print tolower($0)}' | sed 's/[^a-z0-9]//g')
    SESSION_NAME="$GROUP_SANITIZED"`date +%M`

    if [[ -z "$IMAGE_ID" || -z "$GROUP_NAME" || -z "$CONFIG_NAME" ]]; then
        echo "usage $0 image config [image id] [group name] [config name]"
        exit 1
    fi

    EX_HOST=$(grep -A 2 $GROUP_NAME /etc/ansible/hosts | grep '{}' | awk '{print $1}' | sed 's/://g')
    if [[ -z "$EX_HOST" ]]; then
        echo "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
        die "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
    fi

    cray cfs sessions delete "$SESSION_NAME" > /dev/null 2>&1

    verbose_cmd cray cfs sessions create \
        --name "$SESSION_NAME" \
        --configuration-name "$CONFIG_NAME" \
        --target-definition image \
        --target-group "$GROUP_NAME" "$IMAGE_ID" 2>&1

    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] cfs session creation failed! See logs for details"
        die "[$GROUP_NAME] cfs session creation failed! See logs for details"
    fi

    cmd_wait_output "job =" cray cfs sessions describe "$SESSION_NAME"

    JOB_ID=$(cray cfs sessions describe $SESSION_NAME --format json  | jq '.status.session.job' | sed 's/"//g')
    cmd_wait_output "Created pod:" kubectl describe job -n services "$JOB_ID"
    POD_ID=$(kubectl describe job -n services "$JOB_ID" | grep 'Created pod:' | awk '{print $7}')

    cfs_logwatch "$POD_ID"

    cmd_wait_output 'complete' cray cfs sessions describe "$SESSION_NAME"

    cray cfs sessions describe "$SESSION_NAME" --format json | jq '.status.session.succeeded' | grep -q 'true'
    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] image configuation failed"
        die "[$GROUP_NAME] image configuation failed"
    fi

    NEW_IMAGE_ID=$(cray cfs sessions describe "$SESSION_NAME" --format json | jq '.status.artifacts[0].result_id' | sed 's/"//g')

    if [[ -z "$NEW_IMAGE_ID" ]]; then
        echo "[$GROUP_NAME] Could not determine image id for configured image."
        die "[$GROUP_NAME] Could not determine image id for configured image."
    fi
    verbose_cmd cray ims images describe "$NEW_IMAGE_ID"
    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] Error Image Configuration Failed! See logs for details"
        die "[$GROUP_NAME] Error Image Configuration Failed! See logs for details"
    fi

    echo "Image successfully configured"
    echo "[$GROUP_NAME] Configured image created: '$NEW_IMAGE_ID'" 1>&2
    echo "[$GROUP_NAME] Configured image created: '$NEW_IMAGE_ID'"
    RETURN="$NEW_IMAGE_ID"
    return 0
}

function image_clean_deleted_artifacts {
    local ARTIFACTS=()
    local artifact
    ARTIFACTS=( $(cray artifacts list boot-images --format json | jq '.artifacts' | jq '.[].Key' | sed 's/"//g' | grep ^deleted/) )
    for artifact in "${ARTIFACTS[@]}"; do
        cray artifacts delete boot-images "$artifact" | grep -P '\S'
    done
}
