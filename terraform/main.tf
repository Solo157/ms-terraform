# Облачная часть проекта: одна сеть, Managed Kubernetes, Node Group и сервисные
# аккаунты с IAM-ролями. Kubernetes/Helm-объекты (agent, ingress, мониторинг,
# приложение) ставит CI через GitLab Agent — здесь их нет.

resource "yandex_vpc_network" "main" {
  name = "${var.name}-net"
}

resource "yandex_vpc_subnet" "main" {
  name           = "${var.name}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# Единственная SG: трафик внутри VPC, health-check'и LB,
# наружу только 80/443 (ingress).
resource "yandex_vpc_security_group" "main" {
  name       = "${var.name}-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    protocol          = "TCP"
    port              = 10256
    predefined_target = "loadbalancer_healthchecks"
    description       = "Allow Network Load Balancer health checks"
  }

  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["0.0.0.0/0"]
    description    = "Allow Kubernetes NodePort traffic"
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_iam_service_account" "master" {
  name = "${var.name}-master-sa"
}

resource "yandex_iam_service_account" "node" {
  name = "${var.name}-node-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "master_cluster" {
  folder_id = var.yc_folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_vpc" {
  folder_id = var.yc_folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_lb" {
  folder_id = var.yc_folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "master_compute" {
  folder_id = var.yc_folder_id
  role      = "compute.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.master.id}"
}

resource "yandex_kubernetes_cluster" "main" {
  name                    = "${var.name}-cluster"
  network_id              = yandex_vpc_network.main.id
  service_account_id      = yandex_iam_service_account.master.id
  node_service_account_id = yandex_iam_service_account.node.id
  release_channel         = "STABLE"

  cluster_ipv4_range = var.cluster_ipv4_range
  service_ipv4_range = var.service_ipv4_range

  master {
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.main.id]

    zonal {
      zone      = yandex_vpc_subnet.main.zone
      subnet_id = yandex_vpc_subnet.main.id
    }

    maintenance_policy {
      auto_upgrade = true
    }
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.master_cluster,
    yandex_resourcemanager_folder_iam_member.master_vpc,
    yandex_resourcemanager_folder_iam_member.master_lb,
    yandex_resourcemanager_folder_iam_member.master_compute
  ]
}

resource "yandex_kubernetes_node_group" "main" {
  cluster_id = yandex_kubernetes_cluster.main.id
  name       = "${var.name}-nodes"

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.main.id]
      security_group_ids = [yandex_vpc_security_group.main.id]
    }

    resources {
      cores         = var.node_cores
      memory        = var.node_memory
      core_fraction = 100
    }

    boot_disk {
      type = "network-ssd"
      size = var.node_disk_size
    }

    scheduling_policy {
      preemptible = false
    }
  }

  allocation_policy {
    location {
      zone = yandex_vpc_subnet.main.zone
    }
  }

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
  }
}