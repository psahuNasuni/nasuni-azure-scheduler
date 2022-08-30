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

parse_file_nmc_txt() {
    file="$1"

    dos2unix $file
    while IFS="=" read -r key value; do
        case "$key" in
            "nmc_api_endpoint") NMC_API_ENDPOINT="$value" ;;
            "nmc_api_username") NMC_API_USERNAME="$value" ;;
            "nmc_api_password") NMC_API_PASSWORD="$value" ;;
            "nmc_volume_name") NMC_VOLUME_NAME="$value" ;;
            "web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
          esac
        done <"$file"
}

parse_file_NAC_txt() {
    file="$1"

    dos2unix $file
    while IFS="=" read -r key value; do
        case "$key" in
            "acs_resource_group") ACS_RESOURCE_GROUP="$value" ;;
            "acs_admin_app_config_name") ACS_APP_CONFIG_NAME="$value" ;;
            "github_organization") GITHUB_ORGANIZATION="$value" ;;
            "nmc_volume_name") NMC_VOLUME_NAME="$value" ;;
            "azure_location") AZURE_LOCATION="$value" ;;
            "web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
            esac
        done <"$file"
}

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

append_nmc_details_to_config_dat()
{
    UNIFS_TOC_HANDLE=$1
    SOURCE_CONTAINER=$2
    SOURCE_CONTAINER_SAS_URL=$3
	CONFIG_DAT_FILE_NAME="config.dat"
    ### Be careful while modifieng the values
    sed -i "s|\<UniFSTOCHandle\>:.*||g" config.dat
    echo "UniFSTOCHandle: "$UNIFS_TOC_HANDLE >> config.dat
    sed -i "s/SourceContainer:.*/SourceContainer: $SOURCE_CONTAINER/g" config.dat
    sed -i "s|SourceContainerSASURL.*||g" config.dat
    echo "SourceContainerSASURL: "$SOURCE_CONTAINER_SAS_URL >> config.dat
    sed -i '/^$/d' config.dat
}

nmc_api_call(){
    NMC_DETAILS_TXT=$1    
    parse_file_nmc_txt $NMC_DETAILS_TXT
    ### NMC API CALL  ####
    RND=$(( $RANDOM % 1000000 ));
    #'Usage -- python3 fetch_nmc_api_23-8.py <ip_address> <username> <password> <volume_name> <rid> <web_access_appliance_address>')
    python3 fetch_volume_data_from_nmc_api.py $NMC_API_ENDPOINT $NMC_API_USERNAME $NMC_API_PASSWORD $NMC_VOLUME_NAME $RND $WEB_ACCESS_APPLIANCE_ADDRESS
    ### FILTER Values From NMC API Call
    SOURCE_STORAGE_ACCOUNT_NAME=$(cat nmc_api_data_source_storage_account_name.txt)
    UNIFS_TOC_HANDLE=$(cat nmc_api_data_root_handle.txt)
    SOURCE_CONTAINER=$(cat nmc_api_data_source_container.txt)
    SAS_EXPIRY=`date -u -d "300 minutes" '+%Y-%m-%dT%H:%MZ'`
    rm -rf nmc_api_*.txt
    SOURCE_STORAGE_ACCOUNT_KEY=`az storage account keys list --account-name ${SOURCE_STORAGE_ACCOUNT_NAME} | jq -r '.[0].value'`
    SOURCE_CONTAINER_TOCKEN=`az storage account generate-sas --expiry ${SAS_EXPIRY} --permissions r --resource-types co --services b --account-key ${SOURCE_STORAGE_ACCOUNT_KEY} --account-name ${SOURCE_STORAGE_ACCOUNT_NAME} --https-only`
    SOURCE_CONTAINER_TOCKEN=$(echo "$SOURCE_CONTAINER_TOCKEN" | tr -d \")
    SOURCE_CONTAINER_SAS_URL="https://$SOURCE_STORAGE_ACCOUNT_NAME.blob.core.windows.net/?$SOURCE_CONTAINER_TOCKEN"
}

parse_config_file_for_user_secret_keys_values() {
    file="$1"
    while IFS=":" read -r key value; do
        case "$key" in
            "Name") NAC_RESOURCE_GROUP_NAME="$value" ;;
            "AzureSubscriptionID") AZURE_SUBSCRIPTION_ID="$value" ;;
            "DestinationContainer") DESTINATION_CONTAINER_NAME="$value" ;;
            "DestinationContainerSASURL") DESTINATION_CONTAINER_SAS_URL="$value" ;;
        esac
    done <"$file"
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

add_metadat_to_destination_blob(){
    ### Add the metadata to the all files in container of destination blob store 
    DESTINATION_CONTAINER_NAME="$1"
    DESTINATION_CONTAINER_SAS_URL="$2"
    NMC_VOLUME_NAME="$3"
    UNIFS_TOC_HANDLE="$4"

    DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_SAS_URL} | cut -d/ -f3-|cut -d'.' -f1) #"destinationbktsa"
    DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=`az storage account show-connection-string --name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.connectionString'`
    
    echo "INFO ::: Assigning Metadata to all blobs present in destination container  ::: STARTED"
    FILES=`az storage blob list -c $DESTINATION_CONTAINER_NAME --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --query [].name`

    for FILE in $FILES
    do
        if [ "$FILE" == "]" ] || [ "$FILE" == "[" ];then
            continue
        else
            FILE_NAME=$(echo "$FILE" | tr -d '"' | sed 's/\,//g')
            COMMAND="az storage blob metadata update --container-name $DESTINATION_CONTAINER_NAME --name $FILE_NAME --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --connection-string $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING --metadata volume_name=$NMC_VOLUME_NAME toc_handle=$UNIFS_TOC_HANDLE"
            $COMMAND
        fi
    done  
    echo "INFO ::: Assigning Metadata to all blobs present in destination container  ::: COMPLETED"
}

###### START - EXECUTION ######
### GIT_BRANCH_NAME decides the current GitHub branch from Where Code is being executed
GIT_BRANCH_NAME=""
if [[ $GIT_BRANCH_NAME == "" ]]; then
    GIT_BRANCH_NAME="main"
fi
NMC_API_ENDPOINT=""
NMC_API_USERNAME=""
NMC_API_PASSWORD=""
NMC_VOLUME_NAME=""
WEB_ACCESS_APPLIANCE_ADDRESS=""
nmc_api_call "nmc_details.txt"
append_nmc_details_to_config_dat $UNIFS_TOC_HANDLE $SOURCE_CONTAINER $SOURCE_CONTAINER_SAS_URL
parse_file_NAC_txt "NAC.txt"
parse_config_file_for_user_secret_keys_values config.dat 
####################### Check If NAC_RESOURCE_GROUP_NAME is Exist ##############################################
NAC_RESOURCE_GROUP_NAME_STATUS=`az group exists -n ${NAC_RESOURCE_GROUP_NAME} --subscription ${AZURE_SUBSCRIPTION_ID} 2> /dev/null`
if [ "$NAC_RESOURCE_GROUP_NAME_STATUS" = "true" ]; then
   echo "INFO ::: Provided Azure NAC Resource Group Name is Already Exist : $NAC_RESOURCE_GROUP_NAME"
   exit 1
fi
################################################################################################################
ACS_RESOURCE_GROUP=$(echo "$ACS_RESOURCE_GROUP" | tr -d '"')
ACS_APP_CONFIG_NAME=$(echo "$ACS_APP_CONFIG_NAME" | tr -d '"')

##################################### START NAC Provisioning ######################################################################
CONFIG_DAT_FILE_NAME="config.dat"
CONFIG_DAT_FILE_PATH="/usr/local/bin"
sudo chmod 777 $CONFIG_DAT_FILE_PATH
CONFIG_DAT_FILE=$CONFIG_DAT_FILE_PATH/$CONFIG_DAT_FILE_NAME
sudo rm -rf "$CONFIG_DAT_FILE"
cp $CONFIG_DAT_FILE_NAME $CONFIG_DAT_FILE_PATH
NAC_MANAGER_EXIST='N'
FILE=/usr/local/bin/nac_manager
if [ -f "$FILE" ]; then
    echo "INFO ::: NAC Manager Already Available..."
    NAC_MANAGER_EXIST='Y'
else
    echo "INFO ::: NAC Manager not Available. Installing NAC Manager CLI..."
    install_NAC_CLI
fi

echo "INFO ::: current user :-"`whoami`
########## Download NAC Provisioning Code from GitHub ##########
### GITHUB_ORGANIZATION defaults to nasuni-labs
REPO_FOLDER="nasuni-azure-analyticsconnector"
validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
########################### Git Clone : NAC Provisioning Repo ###############################################################
echo "INFO ::: BEGIN - Git Clone !!!"
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
ls
echo "INFO ::: Deleting the Directory: $GIT_REPO_NAME"
rm -rf "${GIT_REPO_NAME}"
pwd
COMMAND="git clone -b $GIT_BRANCH_NAME $GIT_REPO"
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
### Installing dependencies in ./ACSFunction/.python_packages/lib/site-packages location
echo "INFO ::: NAC provisioning ::: Installing Python Dependencies."
COMMAND="pip3 install --target=./ACSFunction/.python_packages/lib/site-packages -r ./ACSFunction/requirements.txt"
$COMMAND
### RUN terraform init
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
echo "INFO ::: NAC provisioning ::: FINISH - Executing ::: Terraform init."

### Check if Resource Group is already provisioned
AZURE_SUBSCRIPTION_ID=$(echo "$AZURE_SUBSCRIPTION_ID" | xargs)

ACS_RG_STATUS=`az group show --name $ACS_RESOURCE_GROUP --query properties.provisioningState --output tsv 2> /dev/null`
if [ "$ACS_RG_STATUS" == "Succeeded" ]; then
    echo "INFO ::: ACS Resource Group $ACS_RESOURCE_GROUP is already exist. Importing the existing Resource Group. "
    COMMAND="terraform import azurerm_resource_group.resource_group /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP"
    $COMMAND
else
    echo "INFO ::: ACS Resource Group $ACS_RESOURCE_GROUP does not exist. It will provision a new Resource Group."
fi

NAC_TFVARS_FILE_NAME="NAC.tfvars"
rm -rf "$NAC_TFVARS_FILE_NAME"

echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$NAC_TFVARS_FILE_NAME
echo "azure_location="\"$AZURE_LOCATION\" >>$NAC_TFVARS_FILE_NAME
echo "acs_admin_app_config_name="\"$ACS_APP_CONFIG_NAME\" >>$NAC_TFVARS_FILE_NAME
echo "web_access_appliance_address="\"$WEB_ACCESS_APPLIANCE_ADDRESS\" >>$NAC_TFVARS_FILE_NAME
echo "nmc_volume_name="\"$NMC_VOLUME_NAME\" >>$NAC_TFVARS_FILE_NAME
echo "unifs_toc_handle="\"$UNIFS_TOC_HANDLE\" >>$NAC_TFVARS_FILE_NAME

### Import Configurations details if exist
INDEX_ENDPOINT_KEY="index-endpoint"
INDEX_ENDPOINT_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key $INDEX_ENDPOINT_KEY --label $INDEX_ENDPOINT_KEY --query value --output tsv 2> /dev/null`
if [ "$INDEX_ENDPOINT_APP_CONFIG_STATUS" != "" ]; then
    echo "INFO ::: index-endpoint already exist in the App Config. Importing the existing index-endpoint. "
    COMMAND="terraform import azurerm_app_configuration_key.$INDEX_ENDPOINT_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_APP_CONFIG_NAME/AppConfigurationKey/$INDEX_ENDPOINT_KEY/Label/$INDEX_ENDPOINT_KEY"
    $COMMAND
else
    echo "INFO ::: $INDEX_ENDPOINT_KEY does not exist. It will provision a new $INDEX_ENDPOINT_KEY."
fi

WEB_ACCESS_APPLIANCE_ADDRESS_KEY="web-access-appliance-address"
WEB_ACCESS_APPLIANCE_ADDRESS_KEY_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key $WEB_ACCESS_APPLIANCE_ADDRESS_KEY --label $WEB_ACCESS_APPLIANCE_ADDRESS_KEY --query value --output tsv 2> /dev/null`
if [ "$WEB_ACCESS_APPLIANCE_ADDRESS_KEY_APP_CONFIG_STATUS" != "" ]; then
    echo "INFO ::: web-access-appliance-address already exist in the App Config. Importing the existing web-access-appliance-address. "
    COMMAND="terraform import azurerm_app_configuration_key.$WEB_ACCESS_APPLIANCE_ADDRESS_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_APP_CONFIG_NAME/AppConfigurationKey/$WEB_ACCESS_APPLIANCE_ADDRESS_KEY/Label/$WEB_ACCESS_APPLIANCE_ADDRESS_KEY"
    $COMMAND
else
    echo "INFO ::: $WEB_ACCESS_APPLIANCE_ADDRESS_KEY does not exist. It will provision a new $WEB_ACCESS_APPLIANCE_ADDRESS_KEY."
fi

NMC_VOLUME_NAME_KEY="nmc-volume-name"
NMC_VOLUME_NAME_KEY_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key $NMC_VOLUME_NAME_KEY --label $NMC_VOLUME_NAME_KEY --query value --output tsv 2> /dev/null`
if [ "$NMC_VOLUME_NAME_KEY_APP_CONFIG_STATUS" != "" ]; then
    echo "INFO ::: nmc-volume-name already exist in the App Config. Importing the nmc-volume-name. "
    COMMAND="terraform import azurerm_app_configuration_key.$NMC_VOLUME_NAME_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_APP_CONFIG_NAME/AppConfigurationKey/$NMC_VOLUME_NAME_KEY/Label/$NMC_VOLUME_NAME_KEY"
    $COMMAND
else
    echo "INFO ::: $NMC_VOLUME_NAME_KEY does not exist. It will provision a new $NMC_VOLUME_NAME_KEY."
fi

UNIFS_TOC_HANDLE_KEY="unifs-toc-handle"
UNIFS_TOC_HANDLE_KEY_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key $UNIFS_TOC_HANDLE_KEY --label $UNIFS_TOC_HANDLE_KEY --query value --output tsv 2> /dev/null`
if [ "$UNIFS_TOC_HANDLE_KEY_APP_CONFIG_STATUS" != "" ]; then
    echo "INFO ::: unifs-toc-handle already exist in the App Config. Importing the unifs-toc-handle."
    COMMAND="terraform import azurerm_app_configuration_key.$UNIFS_TOC_HANDLE_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_APP_CONFIG_NAME/AppConfigurationKey/$UNIFS_TOC_HANDLE_KEY/Label/$UNIFS_TOC_HANDLE_KEY"
    $COMMAND
else
    echo "INFO ::: $UNIFS_TOC_HANDLE_KEY does not exist. It will provision a new $UNIFS_TOC_HANDLE_KEY."
fi


echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "
COMMAND="terraform apply -var-file=$NAC_TFVARS_FILE_NAME -auto-approve"
$COMMAND

DESTINATION_STORAGE_ACCOUNT_NAME=""
DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=""
if [ $? -eq 0 ]; then
    add_metadat_to_destination_blob $DESTINATION_CONTAINER_NAME $DESTINATION_CONTAINER_SAS_URL $NMC_VOLUME_NAME $UNIFS_TOC_HANDLE   
    APP_CONFIG_KEY="index-endpoint"
    ### Read index-endpoint from app config
    FUNCTION_URL=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key $APP_CONFIG_KEY --label $APP_CONFIG_KEY --query value --output tsv 2> /dev/null`
    echo "INFO ::: Fucntion URL : $FUNCTION_URL"
    FUNCTION_APP_NAME=$(echo $FUNCTION_URL | cut -d/ -f3|cut -d. -f1)
    echo "INFO ::: FUNCTION_APP_NAME: $FUNCTION_APP_NAME"
    ### Fetch Connection App Config Connection String
    RES=`az appconfig credential list --name $ACS_APP_CONFIG_NAME --resource-group $ACS_RESOURCE_GROUP --query "[?name=='Primary Read Only'] .connectionString" -o tsv`
    APP_CONFIG_CONNECTION_STRING=$(echo $RES)
    echo "INFO ::: APP_CONFIG_CONNECTION_STRING: $APP_CONFIG_CONNECTION_STRING"
    ### Set Environemnt Variale for App Config Connection String
    SET_ACS_ADMIN_APP_CONFIG_CONNECTION_STRING=`az functionapp config appsettings set --name $FUNCTION_APP_NAME --resource-group $ACS_RESOURCE_GROUP --settings AZURE_APP_CONFIG=$APP_CONFIG_CONNECTION_STRING`
    echo "INFO ::: APP_CONFIG_CONNECTION_STRING: $SET_ACS_ADMIN_APP_CONFIG_CONNECTION_STRING"

    ### Trigger Discovery Function : Discover data from destination bucket and index into the ACS 
    echo "INFO ::: Discovery Function URL ::: $FUNCTION_URL"
    sleep 30
    RES=`curl -X GET -H "Content-Type: application/json" "$FUNCTION_URL"`
    if [ $? -eq 0 ]; then
        echo "INFO ::: Discovery Function Trigger ::: SUCCESS"
    else
        echo "INFO ::: Discovery Function Trigger ::: FAILED"
    fi
    echo "INFO ::: Discovery Function Trigger Response ::: $RES"
    echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
else
    echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
    exit 1
fi

cd ..
##################################### END NAC Provisioning ###################################################################
##################################### Blob Store Cleanup #####################################################################
destination_blob_cleanup(){
	DESTINATION_CONTAINER_NAME="$1"
    DESTINATION_STORAGE_ACCOUNT_NAME="$2"
	DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING="$3"
	ACS_INDEXER_NAME="indexer"
		
    ACS_SERVICE_NAME=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key acs-service-name --label acs-service-name --query value --output tsv 2> /dev/null`
    echo "INFO ::: ACS Service Name : $ACS_SERVICE_NAME"

    ACS_API_KEY=`az appconfig kv show --name $ACS_APP_CONFIG_NAME --key acs-api-key --label acs-api-key --query value --output tsv 2> /dev/null`
    echo "INFO ::: ACS Service API Key : $ACS_API_KEY"

	BLOB_FILE_COUNT=`az storage blob list -c $DESTINATION_CONTAINER_NAME --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --query "length(@)" --connection-string $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING -o tsv`
    echo "INFO ::: BLOB FILE COUNT : $BLOB_FILE_COUNT"
	while :
	do
        sleep 60
		INDEXED_FILE_COUNT=`curl -X GET "https://${ACS_SERVICE_NAME}.search.windows.net/indexers/${ACS_INDEXER_NAME}/status?api-version=2020-06-30&failIfCannotDecrypt=false" -H "Content-Type: application/json" -H "api-key: ${ACS_API_KEY}"`
		INDEXED_FILE_COUNT=$(echo $INDEXED_FILE_COUNT | jq -r .lastResult.itemsProcessed)
		echo "INFO ::: INDEXED_FILE_COUNT : $INDEXED_FILE_COUNT"

		if [[ $BLOB_FILE_COUNT -eq $INDEXED_FILE_COUNT ]];then
			echo "All files are indexed, Start cleanup"
			### Post Indexing Cleanup from Destination Buckets
			echo "INFO ::: Post Indexing Cleanup from Destination Blob Container: $DESTINATION_CONTAINER_NAME ::: STARTED"
			COMMAND="az storage blob delete-batch --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --source $DESTINATION_CONTAINER_NAME --connection-string $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING --verbose"
			$COMMAND
			echo "INFO ::: Post Indexing Cleanup from Destination Blob Container : $DESTINATION_CONTAINER_NAME ::: FINISHED"
			exit 1
		fi
	done
}

# destination_blob_cleanup $DESTINATION_CONTAINER_NAME $DESTINATION_STORAGE_ACCOUNT_NAME $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING
##################################### Blob Store Cleanup END #####################################################################

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
