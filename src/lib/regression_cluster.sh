
function regression_syntax_cluster {
    echo "## cluster"
    function_ok cluster_defaults_config
    function_ok cluster_validate

    echo
}

function regression_cluster {
    echo "## cluster.sh"
    ok "cluster_defaults_config returns ok" cluster_defaults_config
    ok "cluster_validate returns ok" cluster_validate

    echo
}
