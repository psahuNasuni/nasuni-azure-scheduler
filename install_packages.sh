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
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
sudo apt-get update
echo "****************** FINISHED - Install Packages ******************"
