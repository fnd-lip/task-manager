output "cluster_name" {
  description = "Nome do cluster criado"
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Caminho absoluto do kubeconfig"
  value       = abspath(var.kubeconfig_path)
}

output "commands" {
  description = "Comandos úteis após o provisionamento"

  value = {
    get_nodes = "kubectl --kubeconfig=\"${abspath(var.kubeconfig_path)}\" get nodes"

    get_pods = "kubectl --kubeconfig=\"${abspath(var.kubeconfig_path)}\" get pods -A"

    task_manager = "kubectl --kubeconfig=\"${abspath(var.kubeconfig_path)}\" port-forward svc/task-manager 8080:3000"

    grafana = "kubectl --kubeconfig=\"${abspath(var.kubeconfig_path)}\" port-forward svc/monitoring-grafana 3000:80 -n monitoring"

    prometheus = "kubectl --kubeconfig=\"${abspath(var.kubeconfig_path)}\" port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
  }
}

output "application_url" {
  description = "URL local do Task Manager"
  value       = "http://localhost:8080"
}

output "grafana_url" {
  description = "URL local do Grafana"
  value       = "http://localhost:3000"
}

output "loki_datasource_url" {
  description = "URL interna do Loki para configurar no Grafana"
  value       = "http://loki:3100"
}