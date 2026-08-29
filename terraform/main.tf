terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

locals {
  project_path = abspath("${path.module}/..")
  k8s_path     = "${local.project_path}/k8s"
  kubeconfig   = abspath(var.kubeconfig_path)

  # Arquivos usados para detectar alterações na aplicação
  app_files = concat(
    tolist(fileset(local.project_path, "app/**")),
    tolist(fileset(local.project_path, "lib/**")),
    tolist(fileset(local.project_path, "public/**")),
    [
      "Dockerfile",
      "package.json",
      "server.js",
      "next.config.js",
      "postcss.config.js",
      "tailwind.config.js"
    ]
  )

  app_hash = sha256(join("", [
    for file in sort(local.app_files) :
    filesha256("${local.project_path}/${file}")
  ]))

  # Detecta alterações nos manifests Kubernetes
  manifests_hash = sha256(join("", [
    for file in sort(fileset(local.k8s_path, "*.yaml")) :
    filesha256("${local.k8s_path}/${file}")
  ]))
}

# Usa o kubeconfig gerado pelo k3d
provider "helm" {
  kubernetes {
    config_path = local.kubeconfig
  }
}

# Cria o cluster Kubernetes local
resource "null_resource" "k3d_cluster" {
  triggers = {
    cluster_name = var.cluster_name
    node_count   = tostring(var.node_count)
    kubeconfig   = local.kubeconfig
    host_port    = "8501:8501"
  }

  # Cria o cluster k3d
  provisioner "local-exec" {
    command = "k3d cluster create ${var.cluster_name} --servers 1 --agents ${var.node_count} --port 8501:8501@loadbalancer --wait"
  }

  # Aguarda o k3d reconhecer os nós e gera o kubeconfig
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]

    command = <<-EOT
      $tentativas = 0

      do {
        k3d kubeconfig merge ${var.cluster_name} --output "${local.kubeconfig}" --overwrite

        if ($LASTEXITCODE -eq 0) {
          break
        }

        $tentativas++
        Start-Sleep -Seconds 3
      } while ($tentativas -lt 10)

      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }

      (Get-Content "${local.kubeconfig}" -Raw).Replace(
        "host.docker.internal",
        "127.0.0.1"
      ) | Set-Content "${local.kubeconfig}" -Encoding ascii
    EOT
  }

  # Remove o cluster durante o terraform destroy
  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.triggers.cluster_name}"
  }
}

# Constrói a imagem, importa para o k3d e aplica os manifests
resource "null_resource" "deploy_app" {
  depends_on = [null_resource.k3d_cluster]

  triggers = {
    cluster_id     = null_resource.k3d_cluster.id
    app_hash       = local.app_hash
    manifests_hash = local.manifests_hash
  }

  provisioner "local-exec" {
    working_dir = local.project_path
    interpreter = ["PowerShell", "-NoProfile", "-Command"]

    command = <<-EOT
      docker build --provenance=false -t ${var.app_image} .

      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }

      k3d image import ${var.app_image} --cluster ${var.cluster_name} --mode direct

      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }

      $env:KUBECONFIG = "${local.kubeconfig}"
      kubectl apply -f "${local.k8s_path}"

      if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
      }
    EOT
  }
}

# Instala Prometheus e Grafana
resource "helm_release" "kube_prometheus_stack" {
  depends_on = [null_resource.deploy_app]

  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  wait            = true
  timeout         = 900
  cleanup_on_fail = true
}

# Instala Loki e Promtail
resource "helm_release" "loki_stack" {
  depends_on = [
    null_resource.deploy_app,
    helm_release.kube_prometheus_stack
  ]

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = "monitoring"

  wait            = true
  timeout         = 900
  cleanup_on_fail = true

  # Usa a versão indicada no roteiro da aula
  set {
    name  = "loki.image.tag"
    value = "2.9.3"
  }

  # Ativa a coleta de logs dos pods
  set {
    name  = "promtail.enabled"
    value = "true"
  }

  # Evita instalar um segundo Grafana
  set {
    name  = "grafana.enabled"
    value = "false"
  }

  # Evita instalar um segundo Prometheus
  set {
    name  = "prometheus.enabled"
    value = "false"
  }
}