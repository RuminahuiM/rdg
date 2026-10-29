# Settings file of an invented installation (Contoso). Copy it next to your pipeline, change the
# values and keep it in your own repository. Every value is described in infra/variables.tf.

environment   = "prod"
name_prefix   = "rdg"
location      = "switzerlandnorth"
swa_location  = "westeurope"
# automation_location = "switzerlandwest" # only if the Automation quota in location is used up
tenant_domain = "contoso.onmicrosoft.com"

# Start read-only: every run is a dry run until you switch to read-write (and rerun stage 2).
access_mode  = "read-only"
tick_minutes = 15

# Printed by bootstrap stage 1.
state_key_vault_name  = "kv-rdg-prod-bs1a2b"
pipeline_principal_id = "00000000-0000-0000-0000-000000000000"

# Printed by bootstrap stage 2. Leave empty for the first apply (sign-in stays off).
signin_client_id = ""
admin_group_id   = ""
reader_group_id  = ""

alert_emails   = ["it-alerts@contoso.org"]
# Where the alert guide is published; every alert email then links to its section.
# alert_guide_url = "https://example.org/rdg/alerts"
monthly_budget = 50

tags = {
  "cost-center" = "IT"
}
