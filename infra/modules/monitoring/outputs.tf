output "action_group_id" {
  description = "Resource ID of the email action group."
  value       = azurerm_monitor_action_group.email.id
}

output "alert_names" {
  description = "Names of the metric alerts."
  value       = sort(concat([for a in azurerm_monitor_metric_alert.jobs : a.name], [azurerm_monitor_metric_alert.api_errors.name]))
}
