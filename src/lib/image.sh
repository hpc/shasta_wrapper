## image library
# Contains all commands for `shasta image`
# Commands for listing and building images

declare -A IMAGE_ID2NAME
declare -A IMAGE_ID2CREATED

IMAGE_LOGDIR="/var/log/image/"`date '+%Y%m%d-%H%M%S'`

function image {
    case "$1" in
        build)
            shift
            image_build "$@"
            ;;
        build_bare)
            shift
            image_build_bare "$@"
            ;;
        co*)
            shift
            image_configure "$@"
            ;;
        job*)
            shift
            image_job "$@"
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
    echo -e "\tbuild [recipe id] [group] [config] <image name>: build a new bare image from the given recipe"
    echo -e "\tbuild_bare [recipe id] [image name]: build a new bare image from the given recipe"
    echo -e "\tconfigure [image id] [group name] [config name] : build a new image configuring it"
    echo -e "\tdelete [image id] : delete a image"
    echo -e "\tdescribe [image id] : show image information"
    echo -e "\tjob [action]: Manage image jobs"
    echo -e "\tlist : list all images"
    echo -e "\tmap [bos template] [image id] : show image information"

    exit 1
}

## refresh_images
# Get the image data from ims
function refresh_images {
    local RAW image
    echo "# cray ims images list --format json | jq '.[] | \"\\(.created)   \\(.id)   \\(.name)\"' | sed 's/\"//g' | sort"

    IFS=$'\n'
    RAW=( $(rest_api_query "ims/images" | jq '.[] | "\(.id) \(.created) \(.name)"' | sed 's/"//g') )
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

## image_list
# List out the images
function image_list {
    local id name created group
    image_defaults
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

## image_describe
# show inormation on the given image
function image_describe {
    rest_api_query "ims/images/$1" | jq
    return $?
}

## image_delete
# delete the given image
function image_delete {
    if [[ -z "$1" ]]; then
        echo "USAGE: $0 image delete [image1] <images...>" 1>&2
        exit 1
    fi
    for image in "$@"; do
        if [[ -z "$image" ]]; then
            continue
        fi
        echo cray ims images delete --format json "$image" | grep -P '\S'
        rest_api_delete "ims/images/$image"
    done
    echo "Cleaning up image artifacts..."
    image_clean_deleted_artifacts
}

## image_build
# Build a bare image from recipe, and configure it via cfs.
function image_build {
    local EX_HOST BARE_IMAGE_ID CONFIG_IMAGE_ID CONFIG_JOB_NAME RECIPE_ID GROUP_NAME CONFIG_NAME NEW_IMAGE_NAME BOS_TEMPLATE
    OPTIND=1
    while getopts "c:g:i:m:r:t:" OPTION ; do
        case "$OPTION" in
            c) CONFIG_NAME="$OPTARG"; shift ;;
            g) GROUP_NAME="$OPTARG"; shift ;;
            i) NEW_IMAGE_NAME="$OPTARG"; shift ;;
            m) BOS_TEMPLATE="$OPTARG"; shift ;;
            r) RECIPE_ID="$OPTARG"; shift ;;
            t) CONFIG_TAG="$OPTARG"; shift ;;
            \?) die 1 "cfs_apply:  Invalid option:  -$OPTARG" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "$RECIPE_ID" ]]; then
        RECIPE_ID="$1"
        shift
    fi
    if [[ -z "$GROUP_NAME" ]]; then
        GROUP_NAME="$1"
        shift
    fi
    if [[ -z "$CONFIG_NAME" ]]; then
        CONFIG_NAME="$1"
        shift
    fi
    if [[ -z "$NEW_IMAGE_NAME" ]]; then
        NEW_IMAGE_NAME="$1"
        shift
    fi
    if [[ -z "$BOS_TEMPLATE" ]]; then
        BOS_TEMPLATE="$1"
        shift
    fi

    if [[ -z "$RECIPE_ID" || -z "$GROUP_NAME" || -z "$CONFIG_NAME" ]]; then
        echo "USAGE: $0 image build <OPTIONS> [recipe id] [group] [config] <image name>" "<bos template to map to>" 1>&2
        echo "OPTIONS:"
        echo -e "\t -c <cfs config> - Configure the image with this cfs configuration"
        echo -e "\t -i <image name> - Base name to use for the created image"
        echo -e "\t -m <bos template> - Map the final built image to this bos template"
        echo -e "\t -r <recipe id> - Recipe id to build the image from"
        echo -e "\t -t <config tag> - name to use for the applied configuration. This will show on the end of the configured image name"
        exit 1
    fi
    cluster_defaults_config


    EX_HOST=$(grep -A 2 $GROUP_NAME /etc/ansible/hosts | grep '{}' | awk '{print $1}' | sed 's/://g')
    if [[ -z "$EX_HOST" ]]; then
        die "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
    fi

    curl -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/ims/images/$CONFIG_NAME" > /dev/null 2>&1
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
    image_configure -n "$CONFIG_TAG" "$BARE_IMAGE_ID" "$GROUP_NAME" "$CONFIG_NAME" > "$IMAGE_LOGDIR/config-${NEW_IMAGE_NAME}.log"
    if [[ $? -ne 0 ]]; then
        die "[$GROUP_NAME] configure image failed... Not continuing"
    fi
    CONFIG_IMAGE_ID="$RETURN"

    echo "[$GROUP_NAME] Deleting bare image, as it's no longer needed."
    image_delete "$BARE_IMAGE_ID" > /dev/null 2>&1


    if [[ -n "$BOS_TEMPLATE" ]]; then
        image_map "$BOS_TEMPLATE" "$CONFIG_IMAGE_ID" "$GROUP_NAME"
    fi
}

## image_map
# Set the given image to be used in the bos template
function image_map {
    local BOS_TEMPLATE="$1"
    local IMAGE_ID="$2"
    local GROUP="$3"

    if [[ -z "$BOS_TEMPLATE" || -z "$IMAGE_ID" ]]; then
        echo "USAGE: $0 image map [bos template] [image id]" 1>&2
        exit 1
    fi
    IMAGE_RAW=$(curl -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/ims/images" | jq ".[] | select(.id == \"$IMAGE_ID\")")

    IMAGE_ETAG=$(echo "$IMAGE_RAW" | jq '.link.etag' | sed 's/"//g')
    IMAGE_PATH=$(echo "$IMAGE_RAW" | jq '.link.path' | sed 's/"//g')
    if [[ -z "$IMAGE_ETAG" ]]; then
        die "etag could not be found for image: '$IMAGE_ID'. Did you provide a valid image id?"
    fi

    bos_update_template "$BOS_TEMPLATE" ".boot_sets[].etag" "$IMAGE_ETAG"
    if [[ $? -ne 0 ]]; then
        die "Failed to map image id '$IMAGE_ID' to bos template '$BOS_TEMPLATE'" 1>&2
    fi
    bos_update_template "$BOS_TEMPLATE" ".boot_sets[].path" "$IMAGE_PATH"
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

## image_build_bare
# build a bare image from a recipe
function image_build_bare {
    local RECIPE_ID=$1
    local NEW_IMAGE_NAME=$2
    local GROUP_NAME=$3
    local JOB_RAW JOB_ID IMS_JOB_ID POD IMAGE_ID

    if [[ -z "$RECIPE_ID" ]]; then
        echo "usage: $0 image build_bare [recipe id] [image name]"
        exit 1
    fi

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
    cluster_defaults_config
    if [[ -z "$IMS_PUBLIC_KEY_ID" ]]; then
	    die "[$GROUP_NAME] Error! IMS_PUBLIC_KEY_ID is not defined in '/etc/cluster_defaults.conf'"
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

    image_logwatch "$JOB_ID"

    set +e
    cmd_wait_output "success|error" curl -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/ims/jobs/$IMS_JOB_ID"

    curl -s -k -H "Authorization: Bearer ${TOKEN}" "https://api-gw-service-nmn.local/apis/ims/jobs/$IMS_JOB_ID" | grep "status" | grep -q 'success'
    if [[ "$?" -ne 0 ]]; then
        echo "[$GROUP_NAME] Error image build failed! See logs for details"
        die "[$GROUP_NAME] Error image build failed! See logs for details"
    fi

    IMAGE_ID=$(image_describe $IMS_JOB_ID | jq .resultant_image_id | sed 's/"//g' )
    echo "  Grabbing image_id = '$IMAGE_ID' from output..."

    verbose_cmd image_describe "$IMAGE_ID" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] Error image build failed! See logs for details"
        die "[$GROUP_NAME] Error image build failed! See logs for details"
    fi
    echo "  Ok, image does appear to exist. Cleaning up the job..."

    verbose_cmd image_job_delete $IMS_JOB_ID

    echo "[$GROUP_NAME] Bare image Created: $IMAGE_ID" 1>&2
    echo "[$GROUP_NAME] Bare image Created: $IMAGE_ID"
    RETURN="$IMAGE_ID"
    return 0
}

## image_logwatch
# Watch logs for building image kube job
function image_logwatch {
    KUBE_JOB="$1"

    sleep 3
    cmd_wait_output "READY" kubectl get pods -l job-name=$KUBE_JOB -n ims
    POD_ID=$(kubectl get pods -l job-name=$KUBE_JOB -n ims| tail -n 1 | awk '{print $1}')

    verbose_cmd kubectl describe job -n ims $JOB_ID | grep -q 'Pods Statuses:  0 Running / 1 Succeeded'
    RET=$?
    if [[ $RET -eq 0 ]]; then
        echo "[$GROUP_NAME] IMAGE BUILD FAILED: job id '$JOB_ID'"
        die "[$GROUP_NAME] IMAGE BUILD FAILED: job id '$JOB_ID'"
    fi

    echo "################################################"
    echo "#### INFO"
    echo "################################################"
    echo "KUBERNETES JOB: $KUBE_JOB"
    echo "KUBERNETES POD: $POD_ID"
    echo "################################################"
    echo "#### END INFO"
    echo "################################################"

    # Get list of init containers
    INIT_CONTAIN=( $(kubectl get pods "$POD_ID" -n ims -o json |\
        jq '.metadata.managedFields' |\
        jq '.[].fieldsV1."f:spec"."f:initContainers"' |\
        grep -v null |\
        jq 'keys' |\
        grep name |\
        sed 's|  "k:{\\"name\\":\\"||g' |\
        sed 's|\\"}"||g' | \
        sed 's/,//g') )

    # Get list of regular containers
    CONTAIN=( $(kubectl get pods $POD_ID -n ims -o json |\
        jq '.metadata.managedFields' |\
        jq '.[].fieldsV1."f:spec"."f:containers"' |\
        grep -v null |\
        jq 'keys' |\
        grep name |\
        sed 's|  "k:{\\"name\\":\\"||g' |\
        sed 's|\\"}"||g' | \
        sed 's/,//g') )

    # init container logs
    for cont in fetch-recipe wait-for-repos build-ca-rpm; do
        if [[ "$cont" != "build-image" && "$cont" != 'buildenv-sidecar' ]]; then
            echo
            echo
            echo "#################################################"
            echo "### init container: $cont"
            echo "#################################################"
            cmd_wait kubectl logs -n ims -f "$POD_ID" -c $cont
            verbose_cmd kubectl logs -n ims -f "$POD_ID" -c $cont 2>&1
        fi
    done

    # Because the kiwi logs are far more usefull to debugging image builds than 
    # the actual container logs, we go into the container and read from that instead
    echo
    echo
    echo "#################################################"
    echo "### kiwi logs"
    echo "#################################################"
    cmd_wait kubectl exec -ti "$POD_ID" -n ims -c build-image -- ls /mnt/image/kiwi.log 2>&1
    verbose_cmd kubectl exec -ti "$POD_ID" -n ims -c build-image -- tail -f /mnt/image/kiwi.log 2>&1
    echo "#################################################"
    echo "you may get more info from \`kubectl logs -n ims -f $POD -c build-image\`"
    echo "#################################################"
    echo
    echo

}

## image_configure
# Configure an image with cfs
function image_configure {
    local SESSION_NAME EX_HOST JOB_ID POD_ID NEW_IMAGE_ID IMAGE_GROUP OPTIND
    OPTIND=1
    while getopts "n:" OPTION ; do
        case "$OPTION" in
            n) SESSION_NAME="$OPTARG"
            ;;
            \?) die 1 "cfs_apply:  Invalid option:  -$OPTARG" ; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    local IMAGE_ID=$1
    local GROUP_NAME=$2
    local CONFIG_NAME=$3
    cluster_defaults_config

    if [[ -z "$IMAGE_ID" || -z "$GROUP_NAME" || -z "$CONFIG_NAME" ]]; then
        echo "USAGE: $0 image config <OPTIONS> [image id] [group name] [config name]"
        echo "OPTIONS:"
        echo -e "\t-n [name] - set a name for the cfs run instead of the default name"
        exit 1
    fi

    ## Validate group name
    EX_HOST=$(grep -A 2 $GROUP_NAME /etc/ansible/hosts | grep '{}' | awk '{print $1}' | sed 's/://g')
    if [[ -z "$EX_HOST" ]]; then
        echo "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
        die "'$GROUP_NAME' doesn't appear to be a valid group name. Can't locate it in /etc/ansible/hosts"
    fi
    echo "$GROUP_NAME: ${IMAGE_GROUPS[$GROUP_NAME]}"
    if [[ -n "${IMAGE_GROUPS[$GROUP_NAME]}" ]]; then
        IMAGE_GROUP="${IMAGE_GROUPS[$GROUP_NAME]}"
    else
        IMAGE_GROUP="$GROUP_NAME"
    fi

    ## Setup cfs job id
    # We need a group that's lowercase and only containers certain characters 
    # that cfs accepts to use it as the cfs job id
    local GROUP_SANITIZED=$(echo "$GROUP_NAME" | awk '{print tolower($0)}' | sed 's/[^a-z0-9]//g')

    if [[ -z "$SESSION_NAME" ]]; then
        SESSION_NAME="$GROUP_SANITIZED"`date +%M`
    fi

    # Delete any existing cfs session that has the same 
    # name to ensure we don't screw things up
    cfs_job_delete "$SESSION_NAME" > /dev/null 2>&1

    ## Launch the cfs configuration job. 
    # We try multiple times as sometimes cfs is in a bad state and won't 
    # respond (usually responds eventually)
    RETRIES=20
    RET=1
    TRIES=0
    while [[ $RET -ne 0 && $RETRIES -gt $TRIES ]]; do
        if [[ $TRIES -ne 0 ]]; then
            echo
            echo "failed... trying again($TRIES/$RETRIES)"
        fi
    	verbose_cmd cray cfs sessions create \
	    --format json \
    	    --name "$SESSION_NAME" \
    	    --configuration-name "$CONFIG_NAME" \
    	    --target-definition image \
    	    --target-group "$IMAGE_GROUP" "$IMAGE_ID" 2>&1
        RET=$?
	sleep 2
        TRIES=$(($TRIES + 1))
    done

    if [[ $RET -ne 0 ]]; then
        echo "[$GROUP_NAME] cfs session creation failed! See logs for details"
        die "[$GROUP_NAME] cfs session creation failed! See logs for details"
    fi

    ## Show the logs for the cfs configure job
    #
    cmd_wait_output "job" cfs_job_describe "$SESSION_NAME"

    JOB_ID=$(cfs_job_describe $SESSION_NAME  | jq '.status.session.job' | sed 's/"//g')
    cfs_log_job "$SESSION_NAME"

    cmd_wait_output 'complete' cfs_job_describe "$SESSION_NAME"

    cfs_job_describe "$SESSION_NAME" | jq '.status.session.succeeded' | grep -q 'true'
    if [[ $? -ne 0 ]]; then
        echo "[$GROUP_NAME] image configuation failed"
        die "[$GROUP_NAME] image configuation failed"
    fi

    ## Validate that we got an image and set that as the RETURN so that if 
    # parent function wants it it can use it

    NEW_IMAGE_ID=$(cfs_job_describe "$SESSION_NAME" | jq '.status.artifacts[0].result_id' | sed 's/"//g')

    if [[ -z "$NEW_IMAGE_ID" ]]; then
        echo "[$GROUP_NAME] Could not determine image id for configured image."
        die "[$GROUP_NAME] Could not determine image id for configured image."
    fi
    verbose_cmd cray_ims_describe "$NEW_IMAGE_ID"
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

## image_clean_deleted_artifacts
# when telling ims to delete an image, it just marks the artifact as deleted instead of actually deleting it. Thus this goes and deletes any boot-image artifacts marked as deleted.
function image_clean_deleted_artifacts {
    local ARTIFACTS=()
    local artifact
    ARTIFACTS=( $(cray artifacts list boot-images --format json | jq '.artifacts' | jq '.[].Key' | sed 's/"//g' | grep ^deleted/) )
    for artifact in "${ARTIFACTS[@]}"; do
        cray artifacts delete boot-images --format json "$artifact" | grep -P '\S'
    done
}
