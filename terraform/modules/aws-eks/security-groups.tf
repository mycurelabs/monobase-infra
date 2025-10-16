# Security Groups for EKS

# Additional security group for control plane (optional custom rules)
resource "aws_security_group" "cluster_additional" {
  name_prefix = "${var.cluster_name}-cluster-additional-"
  description = "Additional security group for EKS cluster"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-additional"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow cluster to communicate with nodes
resource "aws_security_group_rule" "cluster_to_nodes" {
  description              = "Allow cluster to communicate with nodes"
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster_additional.id
  source_security_group_id = aws_security_group.node_additional.id
}

# Additional security group for nodes
resource "aws_security_group" "node_additional" {
  name_prefix = "${var.cluster_name}-node-additional-"
  description = "Additional security group for EKS nodes"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-node-additional"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_to_node" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node_additional.id
  source_security_group_id = aws_security_group.node_additional.id
}

# Allow nodes to receive traffic from cluster
resource "aws_security_group_rule" "cluster_to_node" {
  description              = "Allow cluster to communicate with nodes"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_additional.id
  source_security_group_id = aws_security_group.cluster_additional.id
}

# Allow nodes to communicate with cluster
resource "aws_security_group_rule" "node_to_cluster" {
  description              = "Allow nodes to communicate with cluster API"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_additional.id
  source_security_group_id = aws_security_group.cluster_additional.id
}

# Allow nodes internet access (for pulling images, etc.)
resource "aws_security_group_rule" "node_egress_internet" {
  description       = "Allow nodes to access internet"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node_additional.id
}
