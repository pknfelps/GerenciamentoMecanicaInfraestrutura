# A base owns all network rules; gateway only attaches its VPC Link to this SG.
resource "aws_security_group" "gateway" {
  name        = "${local.name_prefix}-gateway"
  description = "VPC Link V2 do Gateway; acesso exclusivo ao NLB interno"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-gateway" }
}
# Separate rule avoids a cycle: the NLB ingress references the reserved Gateway SG.
resource "aws_vpc_security_group_egress_rule" "gateway_to_nlb" {
  security_group_id            = aws_security_group.gateway.id
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Gateway acessa somente o NLB interno da API"
  tags                         = { Component = "gateway-network" }
}
