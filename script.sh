#!/bin/bash
#nginx
sudo apt update
sudo apt -y install nginx
sudo service nginx start

#SSM
sudo apt install snapd
sudo snap install amazon-ssm-agent --classic
sudo systemctl enable amazon-ssm-agent 
sudo systemctl start amazon-ssm-agent
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service


