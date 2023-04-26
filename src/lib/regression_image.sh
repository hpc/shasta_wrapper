
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function regression_syntax_image {
    echo "## image"
    function_ok image
    function_ok image_help
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
