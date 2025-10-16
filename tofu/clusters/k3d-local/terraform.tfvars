# k3d Local Development Cluster - Configuration

cluster_name         = "monobase-dev"
k3s_version          = "v1.28.3-k3s1"
servers              = 1
agents               = 2
http_port            = 8080
https_port           = 8443
disable_traefik      = true
install_gateway_api  = true
