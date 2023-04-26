
# © 2023. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.

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
