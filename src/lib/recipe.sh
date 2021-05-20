
declare -A RECIPE_ID2NAME
declare -A RECIPE_ID2CREATED

function recipe {
    case $1 in
        cl*)
            shift
            recipe_clone "$@"
            ;;
        li*)
            shift
            recipe_list "$@"
            ;;
        delete)
            shift
            recipe_delete "$@"
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
    echo -e "\tdelete [recipe id]: delete a recipe"
    echo -e "\tlist : list all recipes"
    
    exit 1
}

function refresh_recipes {
    local RAW SPLIT

    echo "# cray ims recipes list --format json | jq '.[] | "\\\(.id\) \\\(.name\)"' | sed 's/\"//g'"
    IFS=$'\n'
    RAW=( $(cray ims recipes list --format json | jq '.[] | "\(.id) \(.name) \(.created)"' | sed 's/"//g') )
    IFS=$' \t\n'

    for recipe in "${RAW[@]}"; do
        SPLIT=( $recipe )
        id="${SPLIT[0]}"
        name="${SPLIT[1]}"
        created="${SPLIT[2]}"
        RECIPE_ID2NAME[$id]=$name
        RECIPE_ID2CREATED[$id]=$created
    done
}

function recipe_list {
    refresh_recipes
    echo "CREATED                            ID                                     NAME"
    for id in "${!RECIPE_ID2NAME[@]}"; do
        name="${RECIPE_ID2NAME[$id]}"
        created="${RECIPE_ID2CREATED[$id]}"
        echo "$created   $id   $name"
    done | sort
}

function recipe_delete {
     verbose_cmd cray ims recipes delete "$@"
}

function recipe_clone {
    local RECIPE_ID="$1"
    local NEW_RECIPE_NAME="$2"

    local S3_ARTIFACT_BUCKET=ims
    local ARTIFACT_FILE="$RECIPE_NAME.tar.gz"
    local NEW_ARTIFACT_FILE="$NEW_RECIPE_NAME.tar.gz"
    local RAW RECIPE_NAME S3_ARTIFACT_KEY NEW_RECIPE_ID

    set -e
    echo "# cray ims recipes list --format json | jq \".[] | select(.id == \\\"$RECIPE_ID\\\")\""
    RAW=$(cray ims recipes list --format json | jq ".[] | select(.id == \"$RECIPE_ID\")")

    RECIPE_NAME=$(echo "$RAW" | jq '.name' | sed 's/"//g')
    S3_ARTIFACT_KEY=$(echo "$RAW" | jq '.link.path' | sed 's/"//g' | sed 's|^s3://ims/||' )
    mkdir -p $RECIPE_NAME
    verbose_cmd cray artifacts get $S3_ARTIFACT_BUCKET $S3_ARTIFACT_KEY $ARTIFACT_FILE
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

