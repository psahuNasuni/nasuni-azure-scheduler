#!/bin/bash
echo "****************** STARTED - Install Packages  ******************"
sudo apt update
sudo apt upgrade -y
sudo apt install curl bash ca-certificates git openssl wget vim zip unzip dos2unix -y
sudo apt update
echo "****************** Installing Terraform ******************"
sudo wget https://releases.hashicorp.com/terraform/1.1.9/terraform_1.1.9_linux_amd64.zip
sudo unzip *.zip
sudo mv terraform /usr/local/bin/
terraform -v
which terraform
sudo apt install jq -y
echo "****************** Installing Python ******************"
sudo apt install python3 -y
sudo apt install python3-testresources -y
sudo apt install python3-pip -y
sudo pip3 install boto3
echo "******************  Installing AZURE CLI ******************"
sudo apt-get update
sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get install azure-cli
echo "****************** FINISHED - Install Packages ******************"