# Все параметры с дефолтами; секреты сюда не попадают.
# ЗНАЧЕНИЯ ПО УМОЛЧАНИЮ НИЖЕ — ЕДИНСТВЕННЫЙ источник истины для CI: pipeline
# подаёт только yc_cloud_id/yc_folder_id (см. .tf-base), остальное берётся отсюда.
# terraform.tfvars.example обязан совпадать с этими дефолтами, иначе CI и локальный
# запуск расходятся.

variable "name" {
  description = "Префикс имён облачных объектов"
  type        = string
  default     = "otus-ms"
}

variable "yc_cloud_id" {
  description = "ID облака Yandex Cloud"
  type        = string
}

variable "yc_folder_id" {
  description = "ID каталога Yandex Cloud"
  type        = string
}

variable "zone" {
  description = "Зона доступности (одна для подсети, master и нод)"
  type        = string
  default     = "ru-central1-d"
}

variable "subnet_cidr" {
  description = "CIDR единственной подсети VPC"
  type        = string
  default     = "10.97.0.0/16"
  #   default     = "10.10.10.0/24"
}

# CIDR Kubernetes. Задаются ЯВНО (не по умолчанию провайдера), не должны
# пересекаться ни между собой, ни с subnet_cidr. services по умолчанию провайдера
# = 10.96.0.0/16 — оставлен явно, чтобы не зависеть от значений по умолчанию.
variable "cluster_ipv4_range" {
  description = "CIDR для IP-адресов Kubernetes Pod'ов"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_ipv4_range" {
  description = "CIDR для ClusterIP-адресов Kubernetes Service"
  type        = string
  default     = "10.96.0.0/16"
}

variable "node_count" {
  description = "Число воркеров"
  type        = number
  default     = 1
}

variable "node_cores" {
  description = "vCPU на воркер"
  type        = number
  default     = 2
}

variable "node_memory" {
  description = "Память на воркер, ГБ"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Размер загрузочного диска воркера, ГБ"
  type        = number
  # 32 ГБ — минимальный размер boot-диска узла в Managed Kubernetes. 20 ГБ YC
  # отсекает на валидации, поэтому уменьшить ниже 32 нельзя.
  default = 32
}
