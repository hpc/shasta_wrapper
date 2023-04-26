
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

function regression_syntax_recipe {
    echo "## recipe"
    function_ok recipe
    function_ok recipe_help
    function_ok refresh_recipes
    function_ok recipe_list
    function_ok recipe_delete
    function_ok recipe_get
    function_ok recipe_clone
    function_ok recipe_create

    echo
}

function regression_recipe {
    echo "## recipe"
    ok "refresh_recipes returns ok" refresh_recipes
    ok "recipe_list returns ok" recipe_list
    ok_stdout "recipe_list has output" "cray" recipe_list

    echo
}
