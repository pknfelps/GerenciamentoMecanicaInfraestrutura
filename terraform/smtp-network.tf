locals {
  smtp_name      = "${local.name_prefix}-smtp"
  smtp_port      = 2525
  smtp_node_port = 30025
}

# A base reserva o SG; as regras de saida da funcao pertencem ao SAM email.
# Sem regras inline: preservar a administracao das regras pelo consumidor.
resource "aws_security_group" "email" {
  name        = "${local.name_prefix}-email"
  description = "Origem da funcao de captura de email do ambiente"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-email" }
}

resource "aws_security_group_rule" "smtp_from_nlb" {
  type                     = "ingress"
  from_port                = local.smtp_node_port
  to_port                  = local.smtp_node_port
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.nlb.id
  description              = "SMTP4dev aceita o NLB do proprio ambiente"
}

resource "aws_lb_target_group" "smtp" {
  name        = local.smtp_name
  port        = local.smtp_node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = tostring(local.smtp_node_port)
  }

  tags = { Name = local.smtp_name }
}

resource "aws_lb_listener" "smtp" {
  load_balancer_arn = aws_lb.api.arn
  port              = local.smtp_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.smtp.arn
  }
}

# Anexo independente ao mesmo ASG, sem substituir o registro da API.
resource "aws_autoscaling_attachment" "smtp" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.smtp.arn
  depends_on             = [aws_lb_listener.smtp, aws_security_group_rule.smtp_from_nlb]
}
