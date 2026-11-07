# Monitoring: one action group (email), metric alerts on the Automation jobs and the API, and a
# budget on the resource group. No Application Insights or Log Analytics.
# Reference: Monitoring design, "Alerts".

locals {
  automation_namespace = "Microsoft.Automation/automationAccounts"

  # Every alert points to its entry in the alert guide: by section name always, and by link once
  # alert_guide_url is set (the anchor is the alert's key, for example #sync-failed).
  guide = {
    for key, title in {
      sync-failed                = "Sync failed"
      sync-not-running           = "Sync not running"
      job-stuck                  = "Job stuck"
      certificate-renewal-failed = "Certificate renewal failed"
      api-errors                 = "API errors"
    } : key => var.alert_guide_url != "" ? " What to do: ${var.alert_guide_url}#${key}" : " What to do: RDG Alert Guide, section \"${title}\"."
  }

  # TotalJob (dimensions Runbook and Status) on the Automation account.
  job_alerts = merge(
    {
      sync-failed = {
        description = "A sync runbook job failed: at least one definition ended Blocked or Error, or the run itself failed. Open Activity in the web app."
        severity    = 2
        operator    = "GreaterThan"
        threshold   = 0
        window      = "PT15M"
        frequency   = "PT5M"
        runbooks    = var.sync_runbooks
        statuses    = ["Failed"]
      }
      sync-not-running = {
        description = "No Sync-EntraGroups job in the last hour: the schedules are off, the account is broken or Automation is down."
        severity    = 1
        operator    = "LessThan"
        threshold   = 1
        window      = "PT1H"
        frequency   = "PT15M"
        runbooks    = ["Sync-EntraGroups"]
        # No status filter: every job counts. A Status dimension, even with "*", splits the
        # metric per status, and the series "Failed" (0 jobs) would fire while syncs run fine.
        statuses    = []
      }
      job-stuck = {
        description = "A runbook job was suspended or stopped (for example by the 3-hour fair-share limit)."
        severity    = 2
        operator    = "GreaterThan"
        threshold   = 0
        window      = "PT1H"
        frequency   = "PT15M"
        runbooks    = ["*"]
        statuses    = ["Suspended", "Stopped"]
      }
    },
    var.renewal_enabled ? {
      certificate-renewal-failed = {
        description = "Renew-SignInCertificate failed: renewal is broken or the sign-in certificate expires within 21 days. Sign-in stops when it expires."
        severity    = 2
        operator    = "GreaterThan"
        threshold   = 0
        window      = "P1D"
        frequency   = "PT1H"
        runbooks    = ["Renew-SignInCertificate"]
        statuses    = ["Failed"]
      }
    } : {}
  )
}

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-${var.base}"
  resource_group_name = var.resource_group_name
  short_name          = substr("rdg${replace(var.base, "-", "")}", 0, 12)
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = toset(var.alert_emails)

    content {
      name                    = "email-${index(var.alert_emails, email_receiver.value)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "jobs" {
  for_each = local.job_alerts

  name                = "alert-${var.base}-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [var.automation_account_id]
  description         = "${each.value.description}${local.guide[each.key]}"
  severity            = each.value.severity
  window_size         = each.value.window
  frequency           = each.value.frequency
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = local.automation_namespace
    metric_name      = "TotalJob"
    aggregation      = "Total"
    operator         = each.value.operator
    threshold        = each.value.threshold

    dimension {
      name     = "Runbook"
      operator = "Include"
      values   = each.value.runbooks
    }

    dynamic "dimension" {
      for_each = length(each.value.statuses) > 0 ? [each.value.statuses] : []

      content {
        name     = "Status"
        operator = "Include"
        values   = dimension.value
      }
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

resource "azurerm_monitor_metric_alert" "api_errors" {
  name                = "alert-${var.base}-api-errors"
  resource_group_name = var.resource_group_name
  scopes              = [var.function_app_id]
  description         = "The API answered more than 5 server errors in 15 minutes. Check the FunctionAppLogs in the functions storage account.${local.guide["api-errors"]}"
  severity            = 3
  window_size         = "PT15M"
  frequency           = "PT5M"
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

resource "azurerm_consumption_budget_resource_group" "monthly" {
  name              = "budget-${var.base}"
  resource_group_id = var.resource_group_id
  amount            = var.monthly_budget
  time_grain        = "Monthly"

  time_period {
    # First of the current month; only used at creation.
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 80
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.email.id]
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100
    threshold_type = "Forecasted"
    contact_groups = [azurerm_monitor_action_group.email.id]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
