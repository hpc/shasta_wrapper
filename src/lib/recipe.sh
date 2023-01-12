## recipe library
# Contains all commands for `shasta recipe`
# Commands for retrieving and modifying recipes for building images

declare -A RECIPE_ID2NAME
declare -A RECIPE_ID2CREATED
RECIPE_RAW=""

function recipe {
    case "$1" in
        cl*)
            shift
            recipe_clone "$@"
            ;;
        create)
            shift
            recipe_create "$@"
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
        #edit)
        #    shift
        #    recipe_edit "$@"
        #    ;;
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
    echo -e "\tcreate [recipe name] [tar.gz containing recipe data] : create a new recipe"
    echo -e "\tdelete [recipe id] : delete a recipe"
    echo -e "\tget [recipe id] : create a new recipe from existing one"
    echo -e "\tlist : list all recipes"

    exit 1
}

## refresh_recipes
# Gets current list of recipes
function refresh_recipes {
    local SPLIT id created name
    if [[ -n "$RECIPE_RAW" && "$1" != '--force' ]]; then
        return;
    fi

    RECIPE_RAW=$(rest_api_query "ims/recipes" )

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

## recipe_list
# List all available recipes
function recipe_list {
    refresh_recipes
    cluster_defaults_config
    echo "${COLOR_BOLD}CREATED                            ID                                     NAME(default for group)${COLOR_RESET}"
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

## recipe_delete
# Delete the given recipe
function recipe_delete {
    local RECIPE="$1"
    if [[ -z "$RECIPE" ]]; then
        echo "usage: $0 recipe delete <recipe id>"
        exit 1
    fi
    verbose_cmd cray ims recipes delete --format json "$RECIPE"
}

## recipe_get
# Download the given recipe
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

## recipe_clone
# Downloads the recipe, allows you to edit it, then uploads it under a new name
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

    tmpdir
    TMPDIR="$RETURN"
    if [[ -z "$TMPDIR" ]]; then
        die "Error! Could not get tmpdir"
    fi
    cd "$TMPDIR"

    verbose_cmd cray artifacts get $S3_ARTIFACT_BUCKET $S3_ARTIFACT_KEY $ARTIFACT_FILE
    mkdir -p $RECIPE_NAME
    verbose_cmd tar -xzvf $ARTIFACT_FILE -C "$RECIPE_NAME"
    rm -f $ARTIFACT_FILE

    cd $RECIPE_NAME
    echo "image ready for modification. 'exit' when you are done"
    bash


    verbose_cmd tar cvfz ../$NEW_ARTIFACT_FILE .


    echo "# cray ims recipes create --name "$NEW_RECIPE_NAME" --recipe-type kiwi-ng --linux-distribution sles15 --format json"
    NEW_RECIPE_ID=$(cray ims recipes create --name "$NEW_RECIPE_NAME" --recipe-type kiwi-ng --linux-distribution sles15 --format json | jq '.id' | sed 's/"//g')


    verbose_cmd cray artifacts create ims recipes/$NEW_RECIPE_ID/$NEW_ARTIFACT_FILE ../$NEW_ARTIFACT_FILE
    verbose_cmd cray ims recipes update $NEW_RECIPE_ID \
        --link-type s3 \
        --link-path s3://ims/recipes/$NEW_RECIPE_ID/$NEW_ARTIFACT_FILE
    cd -
    rm -rf "$TMPDIR"
    set +e
    set +x
}

## recipe_create
# create a new recipe from the given file and name
function recipe_create {
    local NAME="$1"
    local FILE="$2"
    local NEW_RECIPE_ID	
    ARTIFACT_FILE="$NAME.tar.gz"

    if [[ -z "$FILE" ]]; then
        echo "Usage: $0 recipe create [recipe name] [tarball containing recipe data]"
	exit 1
    fi


    NEW_RECIPE_ID=$(cray ims recipes create --name "$NAME" --recipe-type kiwi-ng --linux-distribution sles15 --format json | jq '.id' | sed 's/"//g')
    verbose_cmd cray artifacts create ims recipes/$RECIPE_ID/$ARTIFACT_FILE $FILE
    verbose_cmd cray ims recipes update $NEW_RECIPE_ID \
        --link-type s3 \
        --link-path s3://ims/recipes/$RECIPE_ID/$ARTIFACT_FILE
}
