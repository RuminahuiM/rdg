output "automation_account_id" {
  description = "Resource ID of the Automation account."
  value       = azurerm_automation_account.this.id
}

output "automation_account_name" {
  description = "Name of the Automation account."
  value       = azurerm_automation_account.this.name
}

output "sync_runbook_names" {
  description = "Names of the two sync runbooks."
  value       = sort(keys(local.sync_runbooks))
}

output "runtime_environment_name" {
  description = "Name of the runtime environment the deploy step imports the runbooks into."
  value       = azurerm_automation_runtime_environment.this.name
}

output "tick_schedules" {
  description = "Tick schedules with the runbooks linked to each, for example { tick-00 = [Sync-EntraGroups, Sync-ExchangeGroups] }."
  value = {
    for name, schedule in azurerm_automation_schedule.tick : schedule.name => sort([
      for key, link in local.job_schedules : link.runbook if format("%02d", link.offset) == name
    ])
  }
}

output "renewal_scheduled" {
  description = "Whether the weekly certificate renewal is scheduled."
  value       = length(azurerm_automation_job_schedule.renewal) == 1
}
