cluster_name = "mycure-k3d-demo"

# Match DOKS prod (1.33), same as vanaheim.
k3s_version = "v1.33.4-k3s1"

servers = 1
agents  = 2

# PUBLIC ingress: the VPS's 80/443 map straight onto k3d's loadbalancer, which
# forwards to the nginx-public-gateway LoadBalancer Service (k3s servicelb).
http_port  = 80
https_port = 443

# Persistent PV storage (Docker creates it on first create). Changing this
# recreates the cluster.
storage_path = "/var/lib/k3d/mycure-k3d-demo"

# Cadence QUIC legs (UDP has no SNI → port-demuxed). Must match the UDP
# listeners in argocd/infrastructure.yaml and cadence.publicAddr in
# values/deployments/mycure-demo.yaml.
extra_port_mappings = [
  "6472:6472/udp@loadbalancer", # cadence hub
  "7842:7842/udp@loadbalancer", # cadence relay
]

# Kubernetes API on LOOPBACK only — this host is on the public internet and
# k3d's default binds the apiserver to 0.0.0.0. kubectl on the VPS uses
# https://127.0.0.1:6445 (k3d writes it into ~/.kube/config).
api_port = "127.0.0.1:6445"
