# k3d Local Development Cluster Configuration

cluster_name        = "k3d-local"
k3s_version         = "v1.28.5-k3s1"
servers             = 1  # Control plane nodes
agents              = 3  # Worker nodes
http_port           = 80
https_port          = 443
disable_traefik     = true  # Use Envoy Gateway instead
install_gateway_api = true
