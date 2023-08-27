#!/bin/bash

set -e

key_vault_name=""
vault_secret_name=""
ado_organization=""
ado_pool=""
agent_count=1
agent_run_once=1
agent_name=$(hostname)
agent_mtu=1400

# Function to get secret from Azure Key Vault using Managed Identity
get_azure_secret() {
  local vault_name=""
  local secret_name=""
  local api_version="2018-02-01"

  # Parse named arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --vault-name) vault_name="$2"; shift ;;
      --secret-name) secret_name="$2"; shift ;;
      *) echo "Unknown parameter: $1"; return 1 ;;
    esac
    shift
  done

  if [[ -z "$vault_name" || -z "$secret_name" ]]; then
    echo "Missing required arguments."
    return 1
  fi

  # Get a token from Azure AD
  local token=$(curl -s -S -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$api_version&resource=https://vault.azure.net" | jq -r .access_token)

  # Check if the token retrieval failed
  if [[ -z "$token" ]]; then
    echo "Failed to get a token from Azure AD."
    return 1
  fi

  # Use the token to retrieve the secret from Key Vault
  local secret=$(curl -s -S -H "Authorization: Bearer $token" "https://$vault_name.vault.azure.net/secrets/$secret_name/?api-version=$api_version" | jq -r .value)

  # Check if the secret retrieval failed
  if [[ -z "$secret" ]]; then
    echo "Failed to get the secret from Key Vault."
    return 1
  fi

  # Output the secret
  echo $secret
}

# Parse named arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --key_vault_name) key_vault_name="$2"; shift ;;
    --vault_secret_name) vault_secret_name="$2"; shift ;;
    --ado_organization) ado_organization="$2"; shift ;;
    --ado_pool) ado_pool="$2"; shift ;;
    --agent_count) agent_count="$2"; shift ;;
    --agent_run_once) agent_run_once="$2"; shift ;;
    --agent_name) agent_name="$2"; shift ;;
    --agent_mtu) agent_mtu="$2"; shift ;;
  esac
  shift
done

if [[ -z "$key_vault_name" || -z "$vault_secret_name" || -z "$ado_organization" || -z "$ado_pool" ]]; then
  echo "Missing required arguments."
  return 1
fi

# Get Azure DevOps PAT token from Azure Key Vault
pat_token=$(get_azure_secret --vault-name $key_vault_name --secret-name $vault_secret_name)

# Install Azure DevOps agent
if [ $agent_count == 1 ]
then
  ./agent-setup.sh "${agent_name}-1" $pat_token $ado_organization $ado_pool $agent_run_once $agent_mtu
else
  ./batch-setup.sh 1 $agent_count $pat_token $ado_organization $ado_pool $agent_run_once $agent_mtu
fi