# NLB interno

`terraform/nlb.tf` administra NLB interno nas duas subnets de workloads, listener TCP 80, target group de instâncias TCP 30080 e `aws_autoscaling_attachment` ao ASG publicado pelo managed node group. A AWS registra/remove os nós sem script ou controller.

`kubernetes/svc-gerenciamento-api.yaml`: NodePort, namespace default, selector app=gerenciamento-api, port 80, nodePort 30080, targetPort 8080, externalTrafficPolicy Cluster. Kube-proxy encaminha ao Pod disponível. Health check HTTP `/health/ready` na porta 30080, sucesso 200. Antes do deploy da API, targets podem estar unhealthy sem impedir o provisionamento da base.

SG NLB sem ingresso direto; egress TCP 30080 ao SG EKS, que aceita essa porta somente do SG NLB. REST VPC Link/PrivateLink recebe avaliação inbound off. Não abrir CIDR da VPC nem internet para contornar teste; a validação de tráfego pelo Gateway ocorre na integração posterior.

SSM base/v2 publica ARN/DNS/SG/target group/porta/protocolo/URI. Terraform é o único proprietário AWS; não usar Service LoadBalancer, Helm ou controller na operação normal. Antes da migração, seguir [limpeza legada](MIGRACAO_DECLARATIVA.md).

Após deploy API, usar comandos AWS padrão para conferir targets e `kubectl port-forward service/svc-gerenciamento-api 8080:80`, seguido de `curl http://localhost:8080/health/ready`, para diagnóstico do serviço. Port-forward valida a aplicação; validação NLB exige o caminho privado/Gateway e saúde dos targets. Descarte Terraform remove associação, listener, NLB e target group antes da rede/EKS conforme dependências.
