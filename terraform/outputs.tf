output "cluster_id" {
  description = "ID кластера — передаётся в CI через dotenv (cluster.env) в job установки агента"
  value       = yandex_kubernetes_cluster.main.id
}

# Контрольные значения сети: справочно (read-атрибут ресурса cluster_ipv4_range в
# провайдере помечен deprecated, поэтому берём из переменных — значения те же).
output "cluster_ipv4_range" {
  description = "CIDR Pod'ов"
  value       = var.cluster_ipv4_range
}

output "service_ipv4_range" {
  description = "CIDR Service'ов"
  value       = var.service_ipv4_range
}

output "subnet_cidr" {
  description = "CIDR подсети VPC"
  value       = yandex_vpc_subnet.main.v4_cidr_blocks[0]
}
