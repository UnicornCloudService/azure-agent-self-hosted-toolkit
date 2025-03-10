#!/bin/bash

set -e

AGENT_USER=$1
AZP_TOKEN=$2
AZP_ORGANIZATION=$3
AZP_PROJECT=$4
POOL=${5:-Default}
USE_RUNONCE=${6:-1}
DOCKER_NETWORK_MTU=${7:-1500}
DOWNLOAD_URL="$(curl -s -L https://github.com/microsoft/azure-pipelines-agent/releases/latest | grep -i vsts-agent-linux-x64 | egrep -o 'https?://[^ "]+')"

if [ -z "$AGENT_USER" ]; then
  echo "Please provide the agent name the first parameter param"
  exit 1
fi

if [ -z "$AZP_TOKEN" ]; then
  echo "Please provide the azp token as the second param"
  exit 1
fi

if [ -z "$AZP_ORGANIZATION" ]; then
  echo "Please provide the azp url as the 3rd param"
  exit 1
fi

if [ -z "$AZP_PROJECT" ]; then
  echo "Please provide the azp project as the 4th param"
  exit 1
fi

if [ -z "$POOL" ]; then
  echo "Please provide the pool as the 5th param"
  exit 1
fi


if [ -z "$USE_RUNONCE" ]; then
  echo "Please provide the run_once enable/disable (0/1) 6th param"
  exit 1
fi


if [ -z "$DOCKER_NETWORK_MTU" ]; then
  echo "Please provide the MTA as 7th param"
  exit 1
fi

export AGENT_ALLOW_RUNASROOT="1"
echo "adding user"
useradd $AGENT_USER -m
usermod -a -G docker $AGENT_USER
export AGENT_USER_HOME=/home/$AGENT_USER
export AGENT_INSTALL_DIR=$AGENT_USER_HOME/agent

echo "Downloading agent"
mkdir -p $AGENT_INSTALL_DIR
curl -f -o $AGENT_INSTALL_DIR/agent.tar.gz $DOWNLOAD_URL
cd $AGENT_INSTALL_DIR
tar -xf agent.tar.gz
rm -f $AGENT_INSTALL_DIR/agent.tar.gz
chown $AGENT_USER:$AGENT_USER $AGENT_USER_HOME -R

echo "configuring agent"
# use ./config.sh --help to find more options
# --replace to replace an agent with the same name (if we redeploy)
su -c "cd $AGENT_INSTALL_DIR && ./config.sh --replace --acceptTeeEula --url "https://dev.azure.com/${AZP_ORGANIZATION}" --auth PAT --token $AZP_TOKEN --pool $POOL --agent $AGENT_USER --projectname $AZP_PROJECT" $AGENT_USER

echo "Adding ENV variables for different aspects / fixes"
# fix docker MTU or the networks created for the docker container will have the wrong (1500) MTA and thus
# fail to do any requests
echo "AGENT_DOCKER_MTU_VALUE=$DOCKER_NETWORK_MTU" >> $AGENT_USER_HOME/agent/.env
# For more options see https://github.com/microsoft/azure-pipelines-agent/blob/master/src/Agent.Sdk/Knob/AgentKnobs.cs#L37

echo "Creating systemd entry for agent $AGENT_USER"
cd $AGENT_USER_HOME/agent/
./svc.sh install $AGENT_USER

if [ $USE_RUNONCE -gt 0 ]; then
  echo "Manipulating system-unit file to use agent-run-once-forever.sh"
  # this is the path patter we borrowed from svc.sh
  SVC_NAME=`systemd-escape --path "vsts.agent.$AZP_ORGANIZATION.$POOL.$AGENT_USER.service"`
  UNIT_FILE_PATH=/etc/systemd/system/${SVC_NAME}

  ESCAPED_RUN_ONCE_PATH='\/opt\/azure-agent-setup\/agent-run-once-forever\.sh'
  sed -i -E "s/^(ExecStart=).*$/\1$ESCAPED_RUN_ONCE_PATH $AGENT_USER/" $UNIT_FILE_PATH
  # we run the startup script as root and drop privileges later. This way we can ensure that the workdir clean
  # does not run into any file permission issues since it runs as root
  sed -i -E "s/^^User=.*$/User=root/" $UNIT_FILE_PATH
  # ensures we can properly manage the lifecycle using the script that wraps the process
  sed -i -E "s/^^KillMode=.*$//" $UNIT_FILE_PATH
fi

echo "Enabling and starting agent"
systemctl enable vsts.agent.$AZP_ORGANIZATION.$POOL.$AGENT_USER
systemctl start vsts.agent.$AZP_ORGANIZATION.$POOL.$AGENT_USER
