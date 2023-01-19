
function regression_syntax_image {
    echo "## image"
    function_ok refresh_images
    function_ok image_list
    function_ok image_describe
    function_ok image_delete
    function_ok image_build
    function_ok image_map
    function_ok image_build_bare
    function_ok image_logwatch
    function_ok image_configure
    function_ok image_clean_deleted_artifacts

    echo
}

function regression_image {
    echo "## image"
    ok "refresh_images returns ok" refresh_images
    ok "image_list returns ok" image_list
    RANDOM_IMAGE=$(echo "${!IMAGE_ID2NAME[@]}" | awk '{print $1}')
    ok "image_describe with random image returns ok" image_describe "$RANDOM_IMAGE" 

    echo
}
