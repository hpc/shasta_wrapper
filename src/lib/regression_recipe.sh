
function regression_syntax_recipe {
    echo "## recipe"
    function_ok recipe
    function_ok recipe_help
    function_ok refresh_recipes
    function_ok recipe_list
    function_ok recipe_delete
    function_ok recipe_clone
    function_ok recipe_edit
}

function regression_recipe {
    echo "## recipe"
    ok "recipe returns ok" recipe
    ok "refresh_recipes returns ok" refresh_recipes
    ok "recipe_list returns ok" recipe_list
    ok_stdout "recipe_list has output" "cos" recipe_list
}
