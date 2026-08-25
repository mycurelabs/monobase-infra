cluster_name = "mycure-onprem-vanaheim"

# Match DOKS prod (1.33) for staging fidelity. Adjust to an available
# rancher/k3s image tag if the pull fails at apply.
k3s_version = "v1.33.4-k3s1"

servers = 1
agents  = 2

# Host ports for k3d's loadbalancer. 8443 is taken by a tailscale-served
# endpoint on this box; ingress is via the tailscale operator anyway, so these
# host ports just need to be free.
http_port  = 18080
https_port = 18443
