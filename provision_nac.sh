#!/bin/bash

#############################################################################################
#### This Script Targets NAC Deployment from any Linux Box
#### Prequisites:
#### 2.1. Software need to be Installed:
####    a- AZURE CLI
####    b- Python 3
####    c- curl
####    d- git
####    e- jq
####    f- wget
####    g- Terraform V 1.0.7
####    h- unzip
####    i- zip
#### 2.2. Azure Subscription
#############################################################################################
set -e

START=$(date +%s)
{
validate_github() {
        GITHUB_ORGANIZATION=$1
        REPO_FOLDER=$2
        if [[ $GITHUB_ORGANIZATION == "" ]];then
                GITHUB_ORGANIZATION="nasuni-labs"
                echo "INFO ::: github_organization not provided as Secret Key-Value pair. So considering nasuni-labs as the default value !!!"
        fi
        GIT_REPO="https://github.com/$GITHUB_ORGANIZATION/$REPO_FOLDER.git"
        echo "INFO ::: git repo $GIT_REPO"
        git ls-remote $GIT_REPO -q
        REPO_EXISTS=$?
        if [ $REPO_EXISTS -ne 0 ]; then
                echo "ERROR ::: Unable to Access the git repo $GIT_REPO. Execution STOPPED"
                exit 1
        else
                echo "INFO ::: git repo accessible. Continue . . . Provisioning . . . "
        fi
}


parse_textfile_for_user_secret_keys_values() {
        file="$1"
        while IFS="=" read -r key value; do
                case "$key" in
                "Name") NAC_RESOURCE_GROUP_NAME="$value" ;;
                "AzureSubscriptionID") AZURE_SUBSCRIPTION_ID="$value" ;;
                "AzureLocation") AZURE_LOCATION="$value" ;;
                "ProductKey") PRODUCT_KEY="$value" ;;
                "SourceContainer") SOURCE_CONTAINER="$value" ;;
                "SourceContainerSASURL") SOURCE_CONTAINER_SAS_URL="$value" ;;
                "VolumeKeySASURL") VOLUME_KEY_SAS_URL="$value" ;;
                "UniFSTOCHandle") UNIFS_TOC_HANDLE="$value" ;;
                "DestinationContainer") DESTINATION_CONTAINER="$value" ;;
        "DestinationContainerSASURL") DESTINATION_CONTAINER_SAS_URL="$value" ;;
        "acs_service_name") ACS_SERVICE_NAME="$value" ;;
        "acs_resource_group") ACS_RESOURCE_GROUP="$value" ;;
        "datasource_connection_string") DATASOURCE_CONNECTION_STRING="$value" ;;
        "web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
                esac
        done <"$file"
}


create_Config_Dat_file() {
### create Config Dat file, which is used for NAC Provisioning
    source $1
    CONFIG_DAT_FILE_NAME="config.dat"
    CONFIG_DAT_FILE_PATH="/usr/local/bin"
    sudo chmod 777 $CONFIG_DAT_FILE_PATH
    CONFIG_DAT_FILE=$CONFIG_DAT_FILE_PATH/$CONFIG_DAT_FILE_NAME
    sudo rm -rf "$CONFIG_DAT_FILE"
    echo "Name: "$NAC_RESOURCE_GROUP_NAME >>$CONFIG_DAT_FILE
    echo "AzureSubscriptionID: "$AZURE_SUBSCRIPTION_ID >>$CONFIG_DAT_FILE
    echo "AzureLocation: "$AZURE_LOCATION>>$CONFIG_DAT_FILE
    echo "ProductKey: "$PRODUCT_KEY>>$CONFIG_DAT_FILE
    echo "SourceContainer: "$SOURCE_CONTAINER >>$CONFIG_DAT_FILE
    echo "SourceContainerSASURL: "$SOURCE_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE
    echo "VolumeKeySASURL: "$VOLUME_KEY_SAS_URL>>$CONFIG_DAT_FILE
    echo "VolumeKeyPassphrase: "\'null\' >>$CONFIG_DAT_FILE
    echo "UniFSTOCHandle: "$UNIFS_TOC_HANDLE >>$CONFIG_DAT_FILE
    echo "PrevUniFSTOCHandle: "null >>$CONFIG_DAT_FILE
    echo "StartingPoint: "/ >>$CONFIG_DAT_FILE
    echo "IncludeFilterPattern: "\'*\' >>$CONFIG_DAT_FILE
    echo "IncludeFilterType: "glob >>$CONFIG_DAT_FILE
    echo "ExcludeFilterPattern: "null >>$CONFIG_DAT_FILE
    echo "ExcludeFilterType: "glob >>$CONFIG_DAT_FILE
    echo "MinFileSizeFilter: "0b >>$CONFIG_DAT_FILE
    echo "MaxFileSizeFilter: "5gb >>$CONFIG_DAT_FILE
    echo "DestinationContainer: "$DESTINATION_CONTAINER >>$CONFIG_DAT_FILE
    echo "DestinationContainerSASURL: "$DESTINATION_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE
    echo "DestinationPrefix: "/ >>$CONFIG_DAT_FILE
    echo "ExcludeTempFiles: "\'True\' >>$CONFIG_DAT_FILE
    sudo chmod 777 $CONFIG_DAT_FILE
}


install_NAC_CLI() {
### Install NAC CLI in the Scheduler machine, which is used for NAC Provisioning
    echo "@@@@@@@@@@@@@@@@@@@@@ STARTED - Installing NAC CLI Package @@@@@@@@@@@@@@@@@@@@@@@"
    sudo wget https://nac.cs.nasuni.com/downloads/nac-manager-1.0.6-linux-x86_64.zip
    sudo unzip '*.zip'
    sudo mv nac_manager /usr/local/bin/
    sudo apt update
    echo "@@@@@@@@@@@@@@@@@@@@@ FINISHED - Installing NAC CLI Package @@@@@@@@@@@@@@@@@@@@@@@"
}

###### START - EXECUTION ####
NMC_VOLUME_NAME="$1"        #### 1st argument to provision_nac.sh
USER_SECRET_TEXT_FILE="$2"  #### 2nd argument to provision_nac.sh
GITHUB_ORGANIZATION="psahuNasuni"

parse_textfile_for_user_secret_keys_values $USER_SECRET_TEXT_FILE
####################### Check If NAC_RESOURCE_GROUP_NAME is Exist ##############################################
NAC_RESOURCE_GROUP_NAME_STATUS=`az group exists -n ${NAC_RESOURCE_GROUP_NAME} --subscription ${AZURE_SUBSCRIPTION_ID}`
if [ "$NAC_RESOURCE_GROUP_NAME_STATUS" = "true" ]; then
   echo "INFO ::: Provided Azure NAC Resource Group Name is Already Exist : $NAC_RESOURCE_GROUP_NAME"
   exit 1
fi
################################################################################################################
ACS_SERVICE_NAME=$(echo "$ACS_SERVICE_NAME" | tr -d '"')
ACS_RESOURCE_GROUP=$(echo "$ACS_RESOURCE_GROUP" | tr -d '"')
KEY_VAULT_ACS_ID="secretacsnac50"
echo  $ACS_SERVICE_NAME
######################## Check If Azure Cognitice Search Available ###############################################

echo "INFO ::: ACS_DOMAIN NAME : $ACS_SERVICE_NAME"
IS_ACS="N"
if [ "$ACS_RESOURCE_GROUP" == "" ] || [ "$ACS_RESOURCE_GROUP" == null ]; then
    echo "INFO ::: Azure Cognitive Search Resource Group is Not provided."
    exit 1
else
    ### If resource group already available
    echo "INFO ::: Azure Cognitive Search Resource Group is provided as $ACS_RESOURCE_GROUP"
fi
if [ "$ACS_SERVICE_NAME" == "" ] || [ "$ACS_SERVICE_NAME" == null ]; then
    echo "INFO ::: Azure Cognitive Search is Not provided."
    exit 1
else
    echo "INFO ::: Provided Azure Cognitive Search name is: $ACS_SERVICE_NAME"

    echo "INFO ::: Checking for ACS Availability Status . . . . "

    ACS_STATUS=`az search service show --name $ACS_SERVICE_NAME --resource-group $ACS_RESOURCE_GROUP | jq -r .status`
    if [ "$ACS_STATUS" == "" ] || [ "$ACS_STATUS" == null ]; then
        echo "INFO ::: ACS not found. Start provisioning ACS"
        IS_ACS="N"
    else
        echo "ACS $ACS_SERVICE_NAME Status is: $ACS_STATUS"
        IS_ACS="Y"
    fi
fi
if [ "$IS_ACS" == "N" ]; then
    echo "INFO ::: Azure Cognitive Search is Not Configured. Need to Provision Azure Cognitive Search Before, NAC Provisioning."
    echo "INFO ::: Begin Azure Cognitive Search Provisioning."
   ########## Download CognitiveSearch Provisioning Code from GitHub ##########
        ### GITHUB_ORGANIZATION defaults to nasuni-labs
        REPO_FOLDER="nasuni-azure-cognitive-search"
    ### https://github.com/psahuNasuni/nasuni-azure-cognitive-search.git
        validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
    ########################### Git Clone  ###############################################################
    echo "INFO ::: BEGIN - Git Clone !!!"
    ### Download Provisioning Code from GitHub
    GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/nasuni-\1/' | cut -d "/" -f 2)
    echo "INFO ::: $GIT_REPO"
    echo "INFO ::: GIT_REPO_NAME $GIT_REPO_NAME"
    pwd
    ls
    echo "INFO ::: Removing ${GIT_REPO_NAME}"
    rm -rf "${GIT_REPO_NAME}"
    pwd
    COMMAND="git clone -b main ${GIT_REPO}"
    $COMMAND
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
    else
        echo "INFO ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
        exit 1
    fi
    cd "${GIT_REPO_NAME}"
    #### RUN terraform init
    echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform init . . . . . . . . "
    COMMAND="terraform init"
    $COMMAND

    chmod 755 $(pwd)/*
    echo "INFO ::: CognitiveSearch provisioning ::: FINISH - Executing ::: Terraform init."
    #### Check if Resource Group is already provisioned
    ACS_RG_STATUS=`az group show --name $ACS_RESOURCE_GROUP --query properties.provisioningState --output tsv`
    if [ "$ACS_RG_STATUS" == "Succeeded" ]; then
        echo "INFO ::: Azure Cognitive Search Resource Group $ACS_RESOURCE_GROUP is already provisioned"
                COMMAND="terraform import azurerm_resource_group.acs_rg /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP"
                $COMMAND
    fi

    ACS_KEY_VAULT_ID_STATUS=`az keyvault show --name $KEY_VAULT_ACS_ID --query properties.provisioningState --output tsv`
    if [ "$ACS_KEY_VAULT_ID_STATUS" == "Succeeded" ]; then
        echo "INFO ::: Azure Key Vault $KEY_VAULT_ACS_ID is already provisioned"
                ACS_KEY_VAULT_ID=`az keyvault show --name $KEY_VAULT_ACS_ID --query id --output tsv`
                COMMAND="terraform import azurerm_key_vault.acs_key_vault $ACS_KEY_VAULT_ID"
                $COMMAND
    fi

    echo "INFO ::: Create TFVARS file for provisioning Cognitive Search"
    ##### Create TFVARS file for provisioning Cognitive Search
    ##### Fetching Active USER PRINCIPAL NAME  #####
    USER_PRINCIPAL_NAME=`az account show --query user.name --output tsv`
    ACS_TFVARS_FILE_NAME="ACS.tfvars"
        rm -rf "$ACS_TFVARS_FILE_NAME"
        echo "acs_service_name="\"$ACS_SERVICE_NAME\" >>$ACS_TFVARS_FILE_NAME
        echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$ACS_TFVARS_FILE_NAME
        echo "azure_location="\"$AZURE_LOCATION\" >>$ACS_TFVARS_FILE_NAME
        echo "acs_key_vault="\"$KEY_VAULT_ACS_ID\" >>$ACS_TFVARS_FILE_NAME
        echo "datasource-connection-string="\"$DATASOURCE_CONNECTION_STRING\" >>$ACS_TFVARS_FILE_NAME
        echo "destination-container-name="\"$DESTINATION_CONTAINER\" >>$ACS_TFVARS_FILE_NAME
        echo "user_principal_name="\"$USER_PRINCIPAL_NAME\" >>$ACS_TFVARS_FILE_NAME
    ##### RUN terraform Apply
    echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
    COMMAND="terraform apply -var-file=$ACS_TFVARS_FILE_NAME -auto-approve"
    $COMMAND

    if [ $? -eq 0 ]; then
        echo "INFO ::: CognitiveSearch provisioning ::: FINISH ::: Executing ::: Terraform apply ::: SUCCESS"
    else
        echo "ERROR ::: CognitiveSearch provisioning ::: FINISH ::: Executing ::: Terraform apply ::: FAILED "
        exit 1
    fi
    cd ..
else
    echo "INFO ::: Azure Cognitive Search is Active . . . . . . . . . ."
    echo "INFO ::: BEGIN ::: NAC Provisioning . . . . . . . . . . . ."
fi

##################################### END Azure CognitiveSearch ###################################################################


##################################### START NAC Provisioning ###################################################################
create_Config_Dat_file "$2"
NAC_MANAGER_EXIST='N'
FILE=/usr/local/bin/nac_manager
if [ -f "$FILE" ]; then
    echo "INFO ::: NAC Manager Already Available..."
    NAC_MANAGER_EXIST='Y'
else
    echo "INFO ::: NAC Manager not Available. Installing NAC Manager..."
    install_NAC_CLI
fi

mkdir "$NMC_VOLUME_NAME"
cd "$NMC_VOLUME_NAME"
pwd
echo "INFO ::: current user :-"`whoami`
########## Download NAC Provisioning Code from GitHub ##########

### GITHUB_ORGANIZATION defaults to nasuni-labs
# https://github.com/psahuNasuni/nasuni-azure-analyticsconnector.git
REPO_FOLDER="nasuni-azure-analyticsconnector"
validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
########################### Git Clone : NAC Provisioning Repo ###############################################################
echo "INFO ::: BEGIN - Git Clone !!!"
#### Download Provisioning Code from GitHub
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
ls
echo "INFO ::: Deleting the Directory: ${GIT_REPO_NAME}"
rm -rf "${GIT_REPO_NAME}"
pwd
COMMAND="git clone -b main ${GIT_REPO}"
$COMMAND
RESULT=$?
if [ $RESULT -eq 0 ]; then
    echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
else
    echo "ERROR ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
    echo "ERROR ::: Unable to Proceed with NAC Provisioning."
    exit 1
fi
pwd
ls -l
########################### Completed - Git Clone  ###############################################################
cd "${GIT_REPO_NAME}"
pwd
ls
#### Installing dependencies in ./ACSFunction/.python_packages/lib/site-packages location
echo "INFO ::: NAC provisioning ::: Installing Python Dependencies."
COMMAND="pip3 install  --target=./ACSFunction/.python_packages/lib/site-packages  -r ./ACSFunction/requirements.txt"
$COMMAND
##### RUN terraform init
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
echo "INFO ::: NAC provisioning ::: FINISH - Executing ::: Terraform init."

#### Check if Resource Group is already provisioned
ACS_RG_STATUS=`az group show --name $ACS_RESOURCE_GROUP --query properties.provisioningState --output tsv`
if [ "$ACS_RG_STATUS" == "Succeeded" ]; then
      echo "INFO ::: Azure Cognitive Search Resource Group $ACS_RESOURCE_GROUP is already provisioned"
      COMMAND="terraform import azurerm_resource_group.resource_group /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP"
      $COMMAND
fi

NAC_TFVARS_FILE_NAME="NAC.tfvars"
rm -rf "$NAC_TFVARS_FILE_NAME"
echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$NAC_TFVARS_FILE_NAME
echo "azure_location="\"$AZURE_LOCATION\" >>$NAC_TFVARS_FILE_NAME
echo "acs_key_vault="\"$KEY_VAULT_ACS_ID\" >>$NAC_TFVARS_FILE_NAME
echo "web_access_appliance_address="\"$WEB_ACCESS_APPLIANCE_ADDRESS\" >>$NAC_TFVARS_FILE_NAME
echo "nmc_volume_name="\"$NMC_VOLUME_NAME\" >>$NAC_TFVARS_FILE_NAME
echo "unifs_toc_handle="\"$UNIFS_TOC_HANDLE\" >>$NAC_TFVARS_FILE_NAME


ACS_KEY_VAULT_SECRET_ID=`az keyvault secret show --name search-endpoint-test --vault-name $KEY_VAULT_ACS_ID --query id --output tsv`
RESULT=$?
if [ $RESULT -eq 0 ]; then
        echo "INFO ::: Key Vault Secret already available ::: Started Importing"
        COMMAND="terraform import azurerm_key_vault_secret.search-endpoint $ACS_KEY_VAULT_SECRET_ID"
        $COMMAND
fi

ACS_KEY_VAULT_SECRET_ID=`az keyvault secret show --name web-access-appliance-address --vault-name $KEY_VAULT_ACS_ID --query id --output tsv`
RESULT=$?
if [ $RESULT -eq 0 ]; then
        echo "INFO ::: Key Vault Secret already available ::: Started Importing"
        COMMAND="terraform import azurerm_key_vault_secret.web-access-appliance-address $ACS_KEY_VAULT_SECRET_ID"
        $COMMAND
fi


ACS_KEY_VAULT_SECRET_ID=`az keyvault secret show --name nmc-volume-name --vault-name $KEY_VAULT_ACS_ID --query id --output tsv`
RESULT=$?
if [ $RESULT -eq 0 ]; then
        echo "INFO ::: Key Vault Secret already available ::: Started Importing"
        COMMAND="terraform import azurerm_key_vault_secret.nmc-volume-name $ACS_KEY_VAULT_SECRET_ID"
        $COMMAND
fi

ACS_KEY_VAULT_SECRET_ID=`az keyvault secret show --name unifs-toc-handle --vault-name $KEY_VAULT_ACS_ID --query id --output tsv`
RESULT=$?
if [ $RESULT -eq 0 ]; then
        echo "INFO ::: Key Vault Secret already available ::: Started Importing"
        COMMAND="terraform import azurerm_key_vault_secret.unifs-toc-handle $ACS_KEY_VAULT_SECRET_ID"
        $COMMAND
fi

echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "

COMMAND="terraform apply -var-file=$NAC_TFVARS_FILE_NAME -auto-approve"
$COMMAND
if [ $? -eq 0 ]; then
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
    else
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
        exit 1
    fi
cd ..
##################################### END NAC Provisioning ###################################################################

REPO_FOLDER="nasuni-azure-userinterface"
validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
########################### Git Clone : userinterface Repo ###############################################################
echo "INFO ::: BEGIN - Git Clone !!!"
#### Download Provisioning Code from GitHub
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
ls
echo "INFO ::: Deleting the Directory: ${GIT_REPO_NAME}"
rm -rf "${GIT_REPO_NAME}"
pwd
COMMAND="git clone -b main ${GIT_REPO}"
$COMMAND
RESULT=$?
if [ $RESULT -eq 0 ]; then
    echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
else
    echo "ERROR ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
    echo "ERROR ::: Unable to Proceed with userinterface Provisioning."
    exit 1
fi
pwd
ls -l
########################### Completed - Git Clone  ###############################################################
##################################### START userinterface Provisioning ###################################################################
cd "${GIT_REPO_NAME}"
pwd
ls
##### RUN terraform init
echo "INFO ::: userinterface provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
echo "INFO ::: userinterface provisioning ::: FINISH - Executing ::: Terraform init."


UI_TFVARS_FILE_NAME="userinterface.tfvars"
rm -rf "$UI_TFVARS_FILE_NAME"
echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$UI_TFVARS_FILE_NAME
echo "acs_key_vault="\"$KEY_VAULT_ACS_ID\" >>$UI_TFVARS_FILE_NAME


echo "INFO ::: userinterface provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "

COMMAND="terraform apply -var-file=$UI_TFVARS_FILE_NAME -auto-approve"
$COMMAND
if [ $? -eq 0 ]; then
        echo "INFO ::: userinterface provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
    else
        echo "INFO ::: userinterface provisioning ::: FINISH ::: Terraform apply ::: FAILED"
        exit 1
    fi
##################################### END userinterface Provisioning ###################################################################


END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
echo "INFO ::: Total execution Time ::: $DIFF"

} || {
    END=$(date +%s)
        secs=$((END - START))
        DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
        echo "INFO ::: Total execution Time ::: $DIFF"
        exit 0
    echo "INFO ::: Failed NAC Povisioning"
}
