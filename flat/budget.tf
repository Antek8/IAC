# envs/dev/budgets.tf

# COST OPTIMIZATION: Add a budget to monitor costs and send alerts.
resource "aws_budgets_budget" "monthly_ec2" {
  name         = "monthly-ec2-cost-budget"
  budget_type  = "COST"
  limit_amount = "100.0" # Set your desired budget limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # FIXED: The argument is 'cost_filter' (singular), not 'cost_filters'.
  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80 # Alert at 80% of the budget
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["antoni.wlodarski@securitykane.com"] # Replace with your email
  }
}
