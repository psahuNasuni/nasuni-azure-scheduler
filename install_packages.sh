#!/bin/bash
echo "****************** STARTED - Install Packages  ******************"
sudo apt update
sudo apt upgrade -y
sudo apt install curl bash ca-certificates git openssl wget vim zip unzip dos2unix -y
sudo apt update
sudo apt  install jq 
echo "***************** Installing Terraform ***************************"
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
echo "****************** Installing Python ******************"
sudo apt install python3 -y
sudo apt install python3-testresources -y
sudo apt install python3-pip -y
sudo pip3 install boto3
sudo pip3 install sortedcontainers
echo "******************  Installing AZURE CLI ******************"
sudo apt-get update
sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get install azure-cli
echo "****************** FINISHED - Install Packages ******************"
