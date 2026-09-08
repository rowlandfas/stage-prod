locals {
  # New Relic CLI installer. It is slow and occasionally hangs, so it is now
  # opt-in: set newrelic_license_key (+ api key / account id) to enable it.
  # The in-container APM agent (baked by Ansible.tf) is unaffected.
  nr_install = var.newrelic_license_key == "" ? "echo 'New Relic CLI install skipped (newrelic_license_key not set)'" : "(curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash && sudo NEW_RELIC_API_KEY=${var.newrelic_api_key} NEW_RELIC_ACCOUNT_ID=${var.newrelic_account_id} NEW_RELIC_REGION=EU /usr/local/bin/newrelic install -y) || true"

  # Endpoints the Jenkins pipeline needs, resolved at apply time and injected as
  # Jenkins global env vars via JCasC (so the Jenkinsfile never hardcodes them).
  rds_endpoint = aws_db_instance.bankapp-db.endpoint
  ansible_host = aws_instance.ansible-server.public_ip
}
