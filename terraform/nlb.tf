locals {
  nlb_name = "${local.name_prefix}-api"
}

# Sem entrada direta. O Gateway utiliza PrivateLink/VPC Link REST (D01).
resource "aws_security_group" "nlb" {
  name        = "${local.name_prefix}-nlb"
  description = "NLB interno da API; entrada somente por PrivateLink"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-nlb" }
  egress {
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
    description     = "Trafego e health checks ao NodePort da API"
  }
}

resource "aws_security_group_rule" "api_from_nlb" {
  type                     = "ingress"
  from_port                = 30080
  to_port                  = 30080
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.nlb.id
  description              = "API aceita o NLB do proprio ambiente"
}

resource "aws_lb" "api" {
  name               = local.nlb_name
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.workload[*].id
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing                             = true
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"
  tags                                                         = { Name = local.nlb_name }
}

resource "aws_lb_target_group" "api" {
  name        = local.nlb_name
  port        = 30080
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
  health_check {
    protocol = "HTTP"
    port     = "30080"
    path     = "/health/ready"
    matcher  = "200"
  }
  tags = { Name = local.nlb_name }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# O ASG registra e remove suas instancias; Terraform nao administra seus IDs.
resource "aws_autoscaling_attachment" "api" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.api.arn
  depends_on             = [aws_lb_listener.api, aws_security_group_rule.api_from_nlb]
}
