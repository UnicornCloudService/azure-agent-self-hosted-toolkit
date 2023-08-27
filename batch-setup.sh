#!/bin/bash

set -e

START_FROM=${1:-1}
AMOUNT=$2
AZP_TOKEN=$3
AZP_ORGANIZATION=$4
POOL=$5
RUN_ONCE_MODE=$6
DOCKER_NETWORK_MTU=$7
agent_name=$(hostname)

if [ -z "$AMOUNT" ]; then
  echo "Please provide the number of agents to setup as the first param"
  exit 1
fi

if [ -z "$AZP_TOKEN" ]; then
  echo "Please provide the azp token as the second param"
  exit 1
fi

echo "Setting up $AMOUNT agents starting with $START_FROM"
for ((i = $START_FROM ; i < ($AMOUNT+$START_FROM) ; i++)); do
  /tmp/azure-agent-self-hosted-toolkit/agent-setup.sh "$agent_name-$i" $AZP_TOKEN $AZP_ORGANIZATION $POOL $RUN_ONCE_MODE $DOCKER_NETWORK_MTU
done
