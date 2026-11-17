# OTUS CI/CD — подготовка инфраструктуры в Yandex Cloud

Учебный демо-проект в **одном GitLab-проекте**: Terraform + Helm (values для
кластерных компонентов) + один GitLab CI pipeline. Готовит инфраструктуру для
будущего приложения: один Managed Kubernetes кластер Yandex Cloud с ingress,
мониторингом и логами. **Самого приложения здесь нет** — проект только
подготавливает платформу под него.

## Архитектура

- **Terraform** (`terraform/`) создаёт только облако: одну VPC, одну подсеть в
  одной зоне, Security Group, один Managed Kubernetes (zonal) с одной Node Group,
  два сервисных аккаунта (master и node) и их IAM-роли. CIDR Pod'ов и Service'ов
  заданы явно (переменные `cluster_ipv4_range`/`service_ipv4_range`) и не
  пересекаются с подсетью. Terraform-провайдеры
  Kubernetes/Helm не используются. Один корень, один remote state в Yandex Object
  Storage (S3-backend).
- **CI разворачивает всё в кластер.** Сначала bootstrap-джоба ставит GitLab Agent
  for Kubernetes (`install_gitlab_agent`). Агент устанавливается и остаётся в
  кластере. Job-ы компонентов (`install_cluster_components`) обращаются к кластеру
  через временный kubeconfig от YC-SA (`yc get-credentials`, живёт только во время
  джобы): в docker-executor «голые» helm/kubectl не могут обратиться через агент
  (нет agent-kubeconfig).
- **Один GitLab Runner** (внешний, тег `yc-runner`) создаётся и настраивается
  вручную оператором до первого запуска.
- Не используются: Yandex Container Registry, prod-окружение/namespace,
  Terraform modules, GitLab Runner из Terraform.

### Кто что делает

| Что | Чем |
|---|---|
| VPC, подсеть, SG, MGKS + Node Group, SA + IAM | Terraform (`terraform/`) |
| GitLab Runner | оператор, вручную (регистрация в проект, тег `yc-runner`) |
| GitLab Agent | CI `install_gitlab_agent` (YC CLI + Helm в ns `gitlab-agent`) |
| ingress-nginx, kube-prometheus-stack, Loki, Alloy | CI `install_cluster_components` (Helm через агент) |
| bucket Object Storage + ключи, SA YC + ключ, агент-токен | оператор, разово (см. «Первоначальная настройка») |

## GitLab CI/CD Variables

Auto (предопределённые GitLab — руками не задавать): `CI_PROJECT_PATH`,
`CI_PIPELINE_SOURCE`, `CI_COMMIT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`. Временный
kubeconfig для helm/kubectl собирается в job-ах через `yc get-credentials`
(env `KUBECONFIG`).

Non-secret (задаёт оператор; значения берутся из GitLab/YC):

| Переменная | Значение |
|---|---|
| `YC_CLOUD_ID` | ID облака YC (из Yandex Cloud) |
| `YC_FOLDER_ID` | ID каталога YC (из Yandex Cloud) |
| `TF_STATE_BUCKET` | имя bucket Object Storage под state |
| `GITLAB_KAS_ADDRESS` | адрес KAS из UI GitLab (`wss://…/-/kubernetes-agent/`) |

Secret (masked):

| Переменная | Назначение |
|---|---|
| `YC_SA_KEY` | JSON-ключ сервисного аккаунта YC, **типа File**: GitLab отдаёт путь к файлу; его читают Terraform (`YC_SERVICE_ACCOUNT_KEY_FILE`) и `yc config set service-account-key` |
| `YC_ACCESS_KEY_ID` / `YC_SECRET_ACCESS_KEY` | статические ключи Object Storage; передаются в S3-backend только как env `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, чтобы не попасть в state |
| `GITLAB_AGENT_TOKEN` | токен агента (`glagent-…`) из UI GitLab. Не путать с токеном раннера (`glrt-…`) |

## Первоначальная настройка (разово, руками)

1. Сервисный аккаунт YC с ролью `editor` на каталог + JSON-ключ → `YC_SA_KEY`
   (тип File). `editor` на каталоге достаточно: он включает `iam.serviceAccounts.user`
   (создать SA) и право назначать роли в этом каталоге (создать folder-`iam_member`
   и `yandex_kubernetes_cluster`). Более узкий набор (iam.user + k8s.admin +
   vpc.admin + …) для демо не вводим — см. требование «не усложнять RBAC».
2. Object Storage: bucket под state + статические ключи (пользователь с
   `storage.editor`) → `YC_ACCESS_KEY_ID`/`YC_SECRET_ACCESS_KEY`, non-secret
   `TF_STATE_BUCKET`.
3. Зарегистрировать существующий внешний GitLab Runner с тегом `yc-runner`
   (Docker executor) в проекте. Runner в Terraform не создаётся.
4. Создать GitLab Agent `otus-agent` в UI + токен агента → `GITLAB_AGENT_TOKEN`.
   В `.gitlab/agents/otus-agent/config.yaml` уже прописан `ci_access` на проект.
5. Задать non-secret: `YC_CLOUD_ID`, `YC_FOLDER_ID`, `TF_STATE_BUCKET`,
   `GITLAB_KAS_ADDRESS`. Ветка деплоя (обычно `main`) — protected.

Порядок файлов Terraform и переменные: значения по умолчанию заданы в
`variables.tf`; в CI required-значения (`yc_cloud_id`, `yc_folder_id`) и bucket
backend'а подаются отдельными переменными, секреты — через env (см. `.gitlab-ci.yml`
джобу `.tf-base`). Локально — скопировать `terraform.tfvars.example` в
`terraform.tfvars` (не коммитить).

## Порядок запуска инфраструктурного пайплайна

Pipeline создаётся для branch, merge request и tag событий; jobs не фильтруются
по изменённым путям. `terraform_validate` и кластерные установки запускаются вручную.

1. `terraform_validate` (стадия `validate`): `cd terraform && terraform fmt -check
   && terraform init -backend=false && terraform validate`.
2. `terraform_plan` (стадия `plan`): `terraform init -reconfigure
   -backend-config=bucket=$TF_STATE_BUCKET` и `terraform plan` (только показывает
   план; сохранённый `tfplan` дальше не используется — apply строит план заново,
   поэтому «Saved plan is stale» исключён).
3. `terraform_apply` (стадия `apply`, **manual**): выполняет свежий
   `terraform apply -input=false -auto-approve`.
4. `install_gitlab_agent` (стадия `bootstrap`, **manual**): независимо от Terraform
   job получает временный kubeconfig по `CLUSTER_NAME` и ставит/обновляет Agent
   в namespace `gitlab-agent`. Кластер к этому моменту должен существовать.
5. `install_cluster_components` (стадия `infrastructure`, **manual**, независимо
   от установки Agent): разворачивает
   ingress-nginx (ждёт внешний IP балансировщика), kube-prometheus-stack (Grafana на
   `grafana.<LB>.nip.io`), Loki и Alloy. Все установки через `helm upgrade
   --install` — повторный запуск безопасен.

Каждая job компонентов получает временный kubeconfig через `yc get-credentials`
и удаляет его в `after_script`. Agent не используется этими CI jobs как транспорт
доступа к Kubernetes: они подключаются напрямую через YC CLI.

## Проверка после развёртывания

- Grafana: `http://grafana.<LB>.nip.io` (`admin`/`admin`). Готовые панели
  kube-prometheus-stack; источник данных Loki добавлен значениями чарта.
- ingress-nginx: у svc `ingress-nginx-controller` проставлен внешний IP балансировщика.
- Loki: в Explore Grafana (источник `Loki`) видны логи подов с метками `namespace`,
  `pod`, `container`.

IP балансировщика: `kubectl -n ingress-nginx get svc ingress-nginx-controller`.
