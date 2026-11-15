terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      # Зафиксировано под версию из .terraform.lock.hcl (0.245.0). Диапазон
      # >= 0.145 слишком широк: допускает установку любой новой минор-версии,
      # которая может поменять поведение create/destroy.
      version = "~> 0.245"
    }
  }
  required_version = ">= 1.5.0"
}
