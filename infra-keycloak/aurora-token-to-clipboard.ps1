# Generates a fresh AWS IAM DB auth token for the Keycloak Aurora cluster and
# copies it to the clipboard - paste into the Password field in DBeaver (or
# any other GUI client). The token is valid for 15 minutes; re-run this
# script before each new connection.
#
# Usage: .\aurora-token-to-clipboard.ps1

$token = aws rds generate-db-auth-token `
  --hostname database-1.cluster-cx6k8y6gc6ri.eu-central-1.rds.amazonaws.com `
  --port 5432 --username postgres --region eu-central-1

$token | Set-Clipboard
Write-Host "Token copied to clipboard (valid for 15 minutes)."
