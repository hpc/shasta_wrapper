
declare -A RECIPE_ID2NAME
declare -A RECIPE_ID2CREATED
RECIPE_RAW=""

function recipe {
    case "$1" in
        cl*)
            shift
            recipe_clone "$@"
            ;;
        get)
            shift
            recipe_get "$@"
            ;;
        li*)
            shift
            recipe_list "$@"
            ;;
        delete)
            shift
            recipe_delete "$@"
            ;;
        edit)
            shift
            recipe_edit "$@"
            ;;
        *)
            recipe_help
            ;;
    esac
}

function recipe_help {
    echo    "USAGE: $0 recipe [action]"
    echo    "DESC: Recipes used to build images from. See 'cray ims recipes' for more detailed options"
    echo    "ACTIONS:"
    echo -e "\tclone [cur recipe id] [new recipe name] : create a new recipe from existing one"
    echo -e "\tdelete [recipe id] : delete a recipe"
    echo -e "\tget [recipe id] : create a new recipe from existing one"
    echo -e "\tlist : list all recipes"

    exit 1
}

function refresh_recipes {
    local SPLIT id created name
    if [[ -n "$RECIPE_RAW" && "$1" != '--force' ]]; then
        return;
    fi

    RECIPE_RAW=$(cray ims recipes list --format json )

    IFS=$'\n'
    RECIPES=( $( echo "$RECIPE_RAW" | jq '.[] | "\(.id) \(.created) \(.name)"' | sed 's/"//g') )
    IFS=$' \t\n'

    for recipe in "${RECIPES[@]}"; do
        SPLIT=( $recipe )
        id="${SPLIT[0]}"
        created="${SPLIT[1]}"
        name="${SPLIT[@]:2}"
        RECIPE_ID2NAME[$id]=$name
        RECIPE_ID2CREATED[$id]=$created
    done
}

function recipe_list {
    refresh_recipes
    cluster_defaults_config
    echo "CREATED                            ID                                     NAME(default for group)"
    for id in "${!RECIPE_ID2NAME[@]}"; do
        name="${RECIPE_ID2NAME[$id]}"
        created="${RECIPE_ID2CREATED[$id]}"
        for group in "${!RECIPE_DEFAULT[@]}"; do
            if [[ "${RECIPE_DEFAULT[$group]}" == "$id" ]]; then
                name="$name$COLOR_BOLD($group)$COLOR_RESET"
            fi
        done
        echo "$created   $id   $name"
    done | sort
}

function recipe_delete {
     verbose_cmd cray ims recipes delete "$@"
}

function recipe_get {
    local RECIPE_ID="$1"
    local FILE="$2"

    local S3_ARTIFACT_BUCKET=ims
    local RECIPE ARTIFACT_FILE
    if [[ -z "$RECIPE_ID" ]]; then
        echo "USAGE: $0 recipe get <recipeid>"
        exit 1
    fi
    refresh_recipes

    RECIPE=$(echo "$RECIPE_RAW" | jq ".[] | select(.id == \"$RECIPE_ID\")")
    if [[ -z "$RECIPE" ]]; then
        die "'$RECIPE_ID' does not exist"
    fi
    RECIPE_NAME=$(echo "$RECIPE" | jq '.name' | sed 's/"//g')
    ARTIFACT_FILE="$RECIPE_NAME.tar.gz"
    S3_ARTIFACT_KEY=$(echo "$RECIPE" | jq '.link.path' | sed 's/"//g' | sed 's|^s3://ims/||' )

    verbose_cmd cray artifacts get $S3_ARTIFACT_BUCKET $S3_ARTIFACT_KEY $ARTIFACT_FILE
}



function recipe_clone {
    local RECIPE_ID="$1"
    local NEW_RECIPE_NAME="$2"

    local S3_ARTIFACT_BUCKET=ims
    local NEW_ARTIFACT_FILE="$NEW_RECIPE_NAME.tar.gz"
    local RECIPE RECIPE_NAME S3_ARTIFACT_KEY ARTIFACT_FILE NEW_RECIPE_ID

    if [[ -z "$RECIPE_ID" || -z "$NEW_RECIPE_NAME" ]]; then
        echo "USAGE $0 recipe clone <recipe id> <new name>"
        exit 1
    fi
    refresh_recipes

    set -e
    echo "# cray ims recipes list --format json | jq \".[] | select(.id == \\\"$RECIPE_ID\\\")\""
    RECIPE=$(echo "$RECIPE_RAW" | jq ".[] | select(.id == \"$RECIPE_ID\")")

    RECIPE_NAME=$(echo "$RECIPE" | jq '.name' | sed 's/"//g')
    ARTIFACT_FILE="$RECIPE_NAME.tar.gz"
    S3_ARTIFACT_KEY=$(echo "$RECIPE" | jq '.link.path' | sed 's/"//g' | sed 's|^s3://ims/||' )
    recipe_get
    mkdir -p $RECIPE_NAME
    tar -xzvf $ARTIFACT_FILE -C "$RECIPE_NAME"
    rm -f $ARTIFACT_FILE

    cd $RECIPE_NAME
    echo "image ready for modification. 'exit' when you are done"
    bash

    verbose_cmd tar cvfz ../$NEW_ARTIFACT_FILE .
    cd -


    NEW_RECIPE_ID=$(cray ims recipes create --name "$NEW_RECIPE_NAME" --recipe-type kiwi-ng --linux-distribution sles15 --format json | jq '.id' | sed 's/"//g')


    verbose_cmd cray artifacts create ims recipes/$NEW_RECIPE_ID/$NEW_ARTIFACT_FILE $NEW_ARTIFACT_FILE
    verbose_cmd cray ims recipes update $NEW_RECIPE_ID \
        --link-type s3 \
        --link-path s3://ims/recipes/$NEW_RECIPE_ID/$NEW_ARTIFACT_FILE
    set +e
    set +x
}

function recipe_edit {
    local RECIPE_ID="$1"

    local S3_ARTIFACT_BUCKET=ims
    local ARTIFACT_FILE
    local RECIPE RECIPE_NAME S3_ARTIFACT_KEY NEW_RECIPE_ID

    set -e
    echo "# cray ims recipes list --format json | jq \".[] | select(.id == \\\"$RECIPE_ID\\\")\""
    refresh_recipes
    RECIPE=$(echo "$RECIPE_RAW" | jq ".[] | select(.id == \"$RECIPE_ID\")")

    RECIPE_NAME=$(echo "$RECIPE" | jq '.name' | sed 's/"//g')
    ARTIFACT_FILE="$RECIPE_NAME.tar.gz"
    S3_ARTIFACT_KEY=$(echo "$RECIPE" | jq '.link.path' | sed 's/"//g' | sed 's|^s3://ims/||' )
    mkdir -p $RECIPE_NAME
    verbose_cmd cray artifacts get $S3_ARTIFACT_BUCKET $S3_ARTIFACT_KEY $ARTIFACT_FILE
    tar -xzvf $ARTIFACT_FILE -C "$RECIPE_NAME"
    rm -f $ARTIFACT_FILE

    cd $RECIPE_NAME
    echo "image ready for modification. 'exit' when you are done"
    bash

    verbose_cmd tar cvfz ../$NEW_ARTIFACT_FILE .
    cd -


    #NEW_RECIPE_ID=$(cray ims recipes create --name "$RECIPE_NAME" --recipe-type kiwi-ng --linux-distribution sles15 --format json | jq '.id' | sed 's/"//g')


    verbose_cmd cray artifacts create ims recipes/$RECIPE_ID/$ARTIFACT_FILE $ARTIFACT_FILE
    verbose_cmd cray ims recipes update $RECIPE_ID \
        --link-type s3 \
        --link-path s3://ims/recipes/$RECIPE_ID/$ARTIFACT_FILE
    set +e
    set +x
}
