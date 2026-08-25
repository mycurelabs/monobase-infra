cluster_name = "mycure-onprem-vanaheim"

# Match DOKS prod (1.33) for staging fidelity. Adjust to an available
# rancher/k3s image tag if the pull fails at apply.
k3s_version = "v1.33.4-k3s1"

servers = 1
agents  = 2
