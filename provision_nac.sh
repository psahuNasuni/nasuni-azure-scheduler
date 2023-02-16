#!/bin/bash
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
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
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
LOG_FILE=provision_nac_$DATE_WITH_TIME.log
(
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
            "acs_admin_app_config_name") ACS_ADMIN_APP_CONFIG_NAME="$value" ;;
            "github_organization") GITHUB_ORGANIZATION="$value" ;;
            "nmc_volume_name") NMC_VOLUME_NAME="$value" ;;
            "azure_location") AZURE_LOCATION="$value" ;;
            "web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
            "user_secret") KEY_VAULT_NAME="$value" ;;
            "sp_application_id") SP_APPLICATION_ID="$value" ;;
            "sp_secret") SP_SECRET="$value" ;;
            "azure_tenant_id") AZURE_TENANT_ID="$value" ;;
            "cred_vault") CRED_VAULT="$value" ;;
            "analytic_service") ANALYTICS_SERVICE="$value" ;;
            "frequency") FREQUENCY="$value" ;;
            "nac_scheduler_name") NAC_SCHEDULER_NAME="$value" ;;
            "use_private_ip") USE_PRIVATE_IP="$value" ;;
            "user_subnet_name") USER_SUBNET_NAME="$value" ;;
            esac
        done <"$file"
}

sp_login(){
    SP_USERNAME=$1
    SP_PASSWORD=$2
    TENANT_ID=$3

    az login --service-principal --tenant $TENANT_ID --username $SP_USERNAME --password $SP_PASSWORD
}

root_login(){
    CRED_VAULT_NAME=$1
    TOKEN=`az account get-access-TOKEN --resource "https://vault.azure.net" | jq -r .accessToken`
    ROOT_USER=`curl -H "Authorization: Bearer $TOKEN" -X GET "https://$CRED_VAULT_NAME.vault.azure.net/secrets/root-user?api-version=2016-10-01" | jq -r .value`
    ROOT_PASSWORD=`curl -H "Authorization: Bearer $TOKEN" -X GET "https://$CRED_VAULT_NAME.vault.azure.net/secrets/root-password?api-version=2016-10-01" | jq -r .value`	

    az login -u $ROOT_USER -p $ROOT_PASSWORD
}

add_appconfig_role_assignment(){

    APPCONFIG_ID=`az appconfig show -n $ACS_ADMIN_APP_CONFIG_NAME -g $ACS_RESOURCE_GROUP | jq -r .id`
    USER_OBJECT_ID=`az ad user show --id $ROOT_USER | jq -r .id`
    APP_ROLE_NAME=`az role assignment list --scope $APPCONFIG_ID  | jq '.[] | select((.principalId == '\"$USER_OBJECT_ID\"') and (.principalType == "User")) | {roleDefinitionName}'| jq -r '.[]'`
    if [[ $APP_ROLE_NAME == "App Configuration Data Owner" ]];then
        echo "INFO ::: App Configuration Data Owner role assignment already exist for USER !!!"
    else
        echo "INFO ::: App Configuration Data Owner role assignment does not exist for USER !!!"
        echo "INFO ::: Creating new App Configuration Data Owner role assignment for new USER !!!"
        CREATE_ROLE=`az role assignment create --assignee $ROOT_USER --role "App Configuration Data Owner" --scope $APPCONFIG_ID`
    fi
}
generate_tracker_json(){
	echo "INFO ::: Updating TRACKER JSON ... "
	ACS_URL=$1
	ACS_REQUEST_URL=$2
	DEFAULT_URL=$3
	FREQUENCY=$4
	USER_SECRET=$5
	CREATED_BY=$6
	CREATED_ON=$7
	TRACKER_NMC_VOLUME_NAME=$8
	ANALYTICS_SERVICE=$9
	MOST_RECENT_RUN=${10}
	CURRENT_STATE=${11}
	LATEST_TOC_HANDLE_PROCESSED=${12}
	NAC_SCHEDULER_NAME=$(echo "${13}" | tr -d '"')
	sudo chmod -R 777 /var/www/Tracker_UI/docs/
	python3 /var/www/Tracker_UI/docs/tracker_json.py $ACS_URL $ACS_REQUEST_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	echo "INFO ::: TRACKER JSON  Updated"
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

append_nmc_details_to_config_dat(){
    UNIFS_TOC_HANDLE=$1
    SOURCE_CONTAINER=$2
    SOURCE_CONTAINER_SAS_URL=$3
    PREV_UNIFS_TOC_HANDLE=$4
	CONFIG_DAT_FILE_NAME="config.dat"
    ### Be careful while modifieng the values
    sed -i "s|\<UniFSTOCHandle\>:.*||g" config.dat
    echo "UniFSTOCHandle: "$UNIFS_TOC_HANDLE >> config.dat
    sed -i "s/SourceContainer:.*/SourceContainer: $SOURCE_CONTAINER/g" config.dat
    sed -i "s|SourceContainerSASURL.*||g" config.dat
    echo "SourceContainerSASURL: "$SOURCE_CONTAINER_SAS_URL >> config.dat
    sed -i "s|\<PrevUniFSTOCHandle\>:.*||g" config.dat
    echo "PrevUniFSTOCHandle: "$PREV_UNIFS_TOC_HANDLE >> config.dat
    sed -i '/^$/d' config.dat
}

nmc_api_call(){
    NMC_DETAILS_TXT=$1    
    parse_file_nmc_txt $NMC_DETAILS_TXT
    ### NMC API CALL  ####
    RND=$(( $RANDOM % 1000000 ))
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
            "vnetResourceGroup") USER_RESOURCE_GROUP_NAME="$value" ;;
            "vnetName") USER_VNET_NAME="$value" ;;
        esac
    done <"$file"
}

install_NAC_CLI() {
    ### Install NAC CLI in the Scheduler machine, which is used for NAC Provisioning
    echo "@@@@@@@@@@@@@@@@@@@@@ STARTED - Installing NAC CLI Package @@@@@@@@@@@@@@@@@@@@@@@"
    ### Check for BETA NAC installation
    if [ "$USE_PRIVATE_IP" = "Y" ]; then
        sudo wget https://nac.cs.nasuni.com/downloads/beta/nac-manager-1.0.7.dev8-linux-x86_64.zip
    else
        sudo wget https://nac.cs.nasuni.com/downloads/nac-manager-1.0.6-linux-x86_64.zip
    fi
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

run_cognitive_search_indexer(){
    ACS_SERVICE_NAME=$1
    ACS_API_KEY=$2
    ACS_INDEXER_NAME="indexer"

    INDEXER_RUN_STATUS=`curl -d -X POST "https://${ACS_SERVICE_NAME}.search.windows.net/indexers/${ACS_INDEXER_NAME}/run?api-version=2021-04-30-Preview" -H "Content-Type:applicauion/json" -H "api-key:${ACS_API_KEY}"`
    if [ $? -eq 0 ]; then
        echo "INFO ::: Cognitive Search Indexer Run ::: SUCCESS"
    else
        echo "INFO ::: Cognitive Search Indexer Run ::: FAILED"
        exit 1
    fi
}

destination_blob_cleanup(){
    DESTINATION_CONTAINER_NAME="$1"
    DESTINATION_CONTAINER_SAS_URL="$2"
    ACS_SERVICE_NAME="$3"
    ACS_API_KEY="$4"
    USE_PRIVATE_IP="$5"
    ACS_INDEXER_NAME="indexer"

    DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_SAS_URL} | cut -d/ -f3-|cut -d'.' -f1) #"destinationbktsa"
    DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=`az storage account show-connection-string --name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.connectionString'`

    BLOB_FILE_COUNT=`az storage blob list -c $DESTINATION_CONTAINER_NAME --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --query "length(@)" --connection-string $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING -o tsv`
    echo "INFO ::: BLOB FILE COUNT : $BLOB_FILE_COUNT"
    while :
    do
        sleep 30
        INDEXED_FILE_COUNT=`curl -X GET "https://${ACS_SERVICE_NAME}.search.windows.net/indexers/${ACS_INDEXER_NAME}/status?api-version=2020-06-30&failIfCannotDecrypt=false" -H "Content-Type:application/json" -H "api-key:${ACS_API_KEY}"`

        FILE_PROCESSED_COUNT=$(echo $INDEXED_FILE_COUNT | jq -r .lastResult.itemsProcessed)
        echo "INFO ::: FILE_PROCESSED_COUNT : $FILE_PROCESSED_COUNT"

        FILE_FAILED_COUNT=$(echo $INDEXED_FILE_COUNT | jq -r .lastResult.itemsFailed)
        echo "INFO ::: FILE_FAILED_COUNT : $FILE_FAILED_COUNT"

        TOTAL_INDEX_FILE_COUNT=$(("$FILE_PROCESSED_COUNT"+"$FILE_FAILED_COUNT"))
        echo "INFO ::: TOTAL_INDEX_FILE_COUNT : $TOTAL_INDEX_FILE_COUNT"

        if [[ $BLOB_FILE_COUNT -eq $TOTAL_INDEX_FILE_COUNT ]];then
            echo "All files are indexed, Start cleanup"
            ### Post Indexing Cleanup from Destination Buckets
            echo "INFO ::: Post Indexing Cleanup from Destination Blob Container: $DESTINATION_CONTAINER_NAME ::: STARTED"
            COMMAND="az storage blob delete-batch --account-name $DESTINATION_STORAGE_ACCOUNT_NAME --source $DESTINATION_CONTAINER_NAME --connection-string $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING --verbose"
            $COMMAND
            echo "INFO ::: Post Indexing Cleanup from Destination Blob Container : $DESTINATION_CONTAINER_NAME ::: FINISHED"
            if [ "$USE_PRIVATE_IP" = "Y" ]; then
                remove_shared_private_access $DESTINATION_CONTAINER_SAS_URL $PRIVATE_CONNECTION_NAME $ENDPOINT_NAME $ACS_URL
            fi
            exit 1
        fi
    done
}

create_shared_private_access(){
    
    DESTINATION_CONTAINER_SAS_URL="$1"
    ACS_URL="$2"
    ENDPOINT_NAME="$3"

    DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_SAS_URL} | cut -d/ -f3-| cut -d'.' -f1)
    DESTINATION_STORAGE_ACCOUNT_RESOURCE_GROUP=`az storage account show -n ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.resourceGroup'`
    DESTINATION_STORAGE_ACCOUNT_ID=`az storage account show -n ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.id'`

    ACS_NAME=$(echo ${ACS_URL} | cut -d/ -f3-| cut -d'.' -f1)

    echo "INFO ::: Shared Private Link Resource Creation ::: STARTED"
    SHARED_LINK=`az search shared-private-link-resource create --name $ENDPOINT_NAME --service-name $ACS_NAME --resource-group $ACS_RESOURCE_GROUP --group-id blob --resource-id "${DESTINATION_STORAGE_ACCOUNT_ID}" --request-message "Please Approve the Request"`
    echo "INFO ::: Shared Private Link Resource Creation ::: FINISHED"
    SHARED_LINK_STATUS=$(echo $SHARED_LINK | jq -r '.properties.status')
    SHARED_LINK_PROVISIONING_STATE=$(echo $SHARED_LINK | jq -r '.properties.provisioningState')

    if [ "$SHARED_LINK_STATUS" == "Pending" ] && [ "$SHARED_LINK_PROVISIONING_STATE" == "Succeeded" ] ; then
     	
        PRIVATE_ENDPOINT_LIST=`az network private-endpoint-connection list -g $DESTINATION_STORAGE_ACCOUNT_RESOURCE_GROUP -n $DESTINATION_STORAGE_ACCOUNT_NAME --type Microsoft.Storage/storageAccounts`

        PRIVATE_CONNECTION_NAME=$(echo "$PRIVATE_ENDPOINT_LIST" | jq '.[]' | jq 'select(.properties.privateEndpoint.id | contains('\"$ENDPOINT_NAME\"'))'| jq -r '.name')

        echo "INFO ::: Approve Private Endpoint Connection ::: STARTED"
        CONNECTION_APPROVE=`az network private-endpoint-connection approve -g $DESTINATION_STORAGE_ACCOUNT_RESOURCE_GROUP -n $PRIVATE_CONNECTION_NAME --resource-name $DESTINATION_STORAGE_ACCOUNT_NAME --type Microsoft.Storage/storageAccounts --description "Request Approved"`
        if [[ "$(echo $CONNECTION_APPROVE | jq -r '.properties.privateLinkServiceConnectionState.status')" == "Approved" ]]; then
            echo "INFO ::: Private Endpoint Connection "$PRIVATE_CONNECTION_NAME" is Approved"
        else
            echo "INFO ::: Private Endpoint Connection "$PRIVATE_CONNECTION_NAME" is NOT Approved"
            exit 1
        fi
    else
        echo "INFO ::: Shared Link "$ENDPOINT_NAME" is NOT Created Properly"
        exit 1
    fi
}

remove_shared_private_access(){
    
    DESTINATION_CONTAINER_SAS_URL="$1"
    PRIVATE_CONNECTION_NAME="$2"
    ENDPOINT_NAME="$3"
    ACS_URL="$4"

    DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_SAS_URL} | cut -d/ -f3-| cut -d'.' -f1)
    DESTINATION_STORAGE_ACCOUNT_RESOURCE_GROUP=`az storage account show -n ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.resourceGroup'`
    
    echo "INFO ::: Delete Private Endpoint Connection ::: STARTED"
    DELETE_PRIVATE_ENDPOINT_CONNECTION=`az network private-endpoint-connection delete -g $DESTINATION_STORAGE_ACCOUNT_RESOURCE_GROUP -n $PRIVATE_CONNECTION_NAME --resource-name $DESTINATION_STORAGE_ACCOUNT_NAME  --type Microsoft.Storage/storageAccounts --yes -y`
    echo "INFO ::: Delete Private Endpoint Connection ::: FINISHED"
    ACS_NAME=$(echo ${ACS_URL} | cut -d/ -f3-| cut -d'.' -f1)

    echo "INFO ::: Delete Shared Private Link Resource ::: STARTED"
    DELETE_SHARED_LINK=`az search shared-private-link-resource delete --name $ENDPOINT_NAME --resource-group $ACS_RESOURCE_GROUP --service-name $ACS_NAME --yes -y`
    echo "INFO ::: Delete Shared Private Link Resource ::: FINISHED"
}

create_azure_function_private_dns_zone_virtual_network_link(){
	AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP="$1"
	AZURE_FUNCTION_VNET_NAME="$2"
	AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME="privatelink.azurewebsites.net"
	AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME=`az network private-dns link vnet list -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -z $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME | jq '.[]' | jq 'select((.virtualNetwork.id | contains('\"$AZURE_FUNCTION_VNET_NAME\"')) and (.virtualNetwork.resourceGroup='\"$AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP\"'))'| jq -r '.name'`
	
	AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS=`az network private-dns link vnet show -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME -z $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	
			
	if [ "$AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS" == "Succeeded" ]; then
		
		echo "INFO ::: Private DNS Zone Virtual Network Link for Azure Function is already exist."
		
	else
		echo "INFO ::: $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME dns zone virtual link does not exist. It will provision a new $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME."
		
		VIRTUAL_NETWORK_ID=`az network vnet show -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $AZURE_FUNCTION_VNET_NAME --query id --output tsv 2> /dev/null`
		LINK_NAME="nacfunctionvnetlink"
		
		echo "STARTED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation ::: $LINK_NAME"
		
		COMMAND="az network private-dns link vnet create -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $LINK_NAME -z $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME -v $VIRTUAL_NETWORK_ID -e False"
		$COMMAND	
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo "COMPLETED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link successfully created ::: $LINK_NAME"
		else
			echo "ERROR ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation failed"
			exit 1
		fi
	fi
}

create_storage_account_private_dns_zone_virtual_network_link(){
	STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP="$1"
	STORAGE_ACCOUNT_VNET_NAME="$2"
	STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME="privatelink.blob.core.windows.net"
		
	STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME=`az network private-dns link vnet list -g $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -z $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME | jq '.[]' | jq 'select((.virtualNetwork.id | contains('\"$STORAGE_ACCOUNT_VNET_NAME\"')) and (.virtualNetwork.resourceGroup='\"$STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP\"'))'| jq -r '.name'`

	STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS=`az network private-dns link vnet show -g $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME -z $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	
			
	if [ "$STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS" == "Succeeded" ]; then
		
		echo "INFO ::: Private DNS Zone Virtual Network Link for Storage Account is already exist."
		
	else
		echo "INFO ::: $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME dns zone virtual link does not exist. It will create a new $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME."
		
		VIRTUAL_NETWORK_ID=`az network vnet show -g $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $STORAGE_ACCOUNT_VNET_NAME --query id --output tsv 2> /dev/null`
		LINK_NAME="nacstoragevnetlink"
		
		echo "STARTED ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation ::: $LINK_NAME"
		
		COMMAND="az network private-dns link vnet create -g $STORAGE_ACCOUNT_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $LINK_NAME -z $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME -v $VIRTUAL_NETWORK_ID -e False"
		$COMMAND	
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo "COMPLETED ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone virtual link successfully created ::: $LINK_NAME"
		else
			echo "ERROR ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation failed"
			exit 1
		fi
	fi		
}

create_azure_function_private_dns_zone(){
	AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP="$1"
	AZURE_FUNCTION_VNET_NAME="$2"
	AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME="privatelink.azurewebsites.net"
	AZURE_FUNCTION_PRIVAE_DNS_ZONE_STATUS=`az network private-dns zone show --resource-group $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	

	if [ "$AZURE_FUNCTION_PRIVAE_DNS_ZONE_STATUS" == "Succeeded" ]; then
		
        echo "INFO ::: Private DNS Zone for Azure Function is already exist."

        create_azure_function_private_dns_zone_virtual_network_link $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP $AZURE_FUNCTION_VNET_NAME

	else
		echo "INFO ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone does not exist. It will create a new $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME."
		
		echo "STARTED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone creation"
		
		COMMAND="az network private-dns zone create -g $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME"
		$COMMAND
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo "COMPLETED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone successfully created"
			create_azure_function_private_dns_zone_virtual_network_link $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP $AZURE_FUNCTION_VNET_NAME
		else
			echo "ERROR ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone creation failed"
			exit 1
		fi
	fi
}

create_storage_account_private_dns_zone(){
	STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_RESOURCE_GROUP="$1"
	STORAGE_ACCOUNT_VNET_NAME="$2"
	STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME="privatelink.blob.core.windows.net"
	STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_STATUS=`az network private-dns zone show --resource-group $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	

	if [ "$STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_STATUS" == "Succeeded" ]; then
		
        echo "INFO ::: Private DNS Zone for Storage Account is already exist."

        create_storage_account_private_dns_zone_virtual_network_link $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_RESOURCE_GROUP $STORAGE_ACCOUNT_VNET_NAME

	else
		echo "INFO ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone does not exist. It will create a new $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME."
		
		echo "STARTED ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone creation"
		
		COMMAND="az network private-dns zone create -g $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME"
		$COMMAND
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo "COMPLETED ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone successfully created"
			create_storage_account_private_dns_zone_virtual_network_link $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_RESOURCE_GROUP $STORAGE_ACCOUNT_VNET_NAME
		else
			echo "ERROR ::: $STORAGE_ACCOUNT_PRIVAE_DNS_ZONE_NAME dns zone creation failed"
			exit 1
		fi
	fi
}


get_subnets(){
    VNET_RESOURCE_GROUP="$1"
    USER_VNET_NAME="$2"
    SUBNET_NAME="$3"
    SUBNET_MASK="$4"
    REQUIRED_SUBNET_COUNT="$5"

    DIRECTORY=$(pwd)
    echo "Directory: $DIRECTORY"
    FILENAME="$DIRECTORY/create_subnet_infra.py"
    chmod 777 $FILENAME
    OUTPUT=$(python3 $FILENAME $VNET_RESOURCE_GROUP $USER_VNET_NAME $SUBNET_NAME $SUBNET_MASK $REQUIRED_SUBNET_COUNT 2>&1 >/dev/null > available_subnets.txt)
    COUNTER=0
    NAC_SUBNETS=()
    DISCOVERY_OUTBOUND_SUBNET=()
    SUBNET_LIST=(`cat available_subnets.txt`)
    echo "Subnet list from file : $SUBNET_LIST"
    # Use comma as separator and apply as pattern
    for SUBNET in ${SUBNET_LIST//,/ }
    do
        if [ $COUNTER -lt 16 ]; then
            if [ $COUNTER -eq 0 ]; then
                NAC_SUBNETS+="$SUBNET"
            else
                NAC_SUBNETS+=", $SUBNET"	
            fi
        else
            if [ $COUNTER -eq 16 ]; then
                DISCOVERY_OUTBOUND_SUBNET="[$SUBNET"
            else
                SEARCH_OUTBOUND_SUBNET="$SUBNET"
            fi
        fi
    let COUNTER=COUNTER+1
    done
    NAC_SUBNETS+="]"	
    NAC_SUBNETS=$(echo "$NAC_SUBNETS" | sed 's/ //g')
    DISCOVERY_OUTBOUND_SUBNET=$(echo "$DISCOVERY_OUTBOUND_SUBNET" | sed 's/ //g')
}

###### START - EXECUTION ######
### GIT_BRANCH_NAME decides the current GitHub branch from Where Code is being executed
GIT_BRANCH_NAME="CTPROJECT-457"
if [[ $GIT_BRANCH_NAME == "" ]]; then
    GIT_BRANCH_NAME="main"
fi
NMC_API_ENDPOINT=""
NMC_API_USERNAME=""
NMC_API_PASSWORD=""
NMC_VOLUME_NAME=""
WEB_ACCESS_APPLIANCE_ADDRESS=""
DESTINATION_STORAGE_ACCOUNT_NAME=""
DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=""
PRIVATE_CONNECTION_NAME=""
ROOT_USER=""
ENDPOINT_NAME="acs-private-connection"
parse_file_NAC_txt "NAC.txt" 
sp_login $SP_APPLICATION_ID $SP_SECRET $AZURE_TENANT_ID
root_login $CRED_VAULT
ACS_RESOURCE_GROUP=$(echo "$ACS_RESOURCE_GROUP" | tr -d '"')
ACS_ADMIN_APP_CONFIG_NAME=$(echo "$ACS_ADMIN_APP_CONFIG_NAME" | tr -d '"')
add_appconfig_role_assignment
USE_PRIVATE_IP=$(echo "$USE_PRIVATE_IP" | tr -d '"')
##################################### START TRACKER JSON Creation ###################################################################

echo "NAC_Activity : Export In Progress"
ACS_URL=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key nmc-api-acs-url --label nmc-api-acs-url --query value --output tsv 2> /dev/null`
ACS_REQUEST_URL=$ACS_URL"/indexes/index/docs?api-version=2021-04-30-Preview&search=*"
DEFAULT_URL="/search/index.html"
FREQUENCY=$(echo "$FREQUENCY" | tr -d '"')
USER_SECRET=$KEY_VAULT_NAME
CREATED_BY=$(echo "$SP_APPLICATION_ID" | tr -d '"')
CREATED_ON=$(date "+%Y%m%d-%H%M%S")
TRACKER_NMC_VOLUME_NAME=$NMC_VOLUME_NAME
ANALYTICS_SERVICE=$(echo "$ANALYTICS_SERVICE" | tr -d '"')
MOST_RECENT_RUN=$(date "+%Y:%m:%d-%H:%M:%S")
CURRENT_STATE="Export-In-progress"
LATEST_TOC_HANDLE_PROCESSED="null"
NAC_SCHEDULER_NAME=$(echo "$NAC_SCHEDULER_NAME" | tr -d '"')
echo "INFO ::: NAC scheduler name: " ${NAC_SCHEDULER_NAME}
JSON_FILE_PATH="/var/www/Tracker_UI/docs/${NAC_SCHEDULER_NAME}_tracker.json"
echo "INFO ::: JSON_FILE_PATH:" $JSON_FILE_PATH
if [ -f "$JSON_FILE_PATH" ] ; then
	TRACEPATH="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	TRACKER_JSON=$(cat $JSON_FILE_PATH)
	echo "Tracker json" $TRACKER_JSON
	LATEST_TOC_HANDLE_PROCESSED=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
	#if [ -z "$LATEST_TOC_HANDLE_PROCESSED" -a "$LATEST_TOC_HANDLE_PROCESSED" == " " ]; then	
	if [ -z "$LATEST_TOC_HANDLE_PROCESSED" ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == " " ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == "null" ]; then	
 		LATEST_TOC_HANDLE_PROCESSED="null"
	fi
	echo "INFO LATEST_TOC_HANDLE PROCESSED"  $LATEST_TOC_HANDLE_PROCESSED
fi

generate_tracker_json $ACS_URL $ACS_REQUEST_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
pwd
echo "INFO ::: current user :-"`whoami`
################################################

nmc_api_call "nmc_details.txt"
echo "UNIFS TOC HANDLE: $UNIFS_TOC_HANDLE"
echo "LATEST TOC HANDLE PROCESSED: $LATEST_TOC_HANDLE_PROCESSED"

if [[ "$UNIFS_TOC_HANDLE" == "$LATEST_TOC_HANDLE_PROCESSED" ]]; then
    echo "INFO ::: Previous TOC handle is same as Latest TOC handle. Files are already moved to Destination Bucket."
    exit 1
fi

append_nmc_details_to_config_dat $UNIFS_TOC_HANDLE $SOURCE_CONTAINER $SOURCE_CONTAINER_SAS_URL $LATEST_TOC_HANDLE_PROCESSED
parse_config_file_for_user_secret_keys_values config.dat
 
USER_RESOURCE_GROUP_NAME=$(echo $USER_RESOURCE_GROUP_NAME | tr -d ' ')
USER_VNET_NAME=$(echo $USER_VNET_NAME | tr -d ' ')
AZURE_SUBSCRIPTION_ID=$(echo $AZURE_SUBSCRIPTION_ID | tr -d ' ')

if [ "$USE_PRIVATE_IP" = "Y" ]; then
    create_shared_private_access $DESTINATION_CONTAINER_SAS_URL $ACS_URL $ENDPOINT_NAME
fi

NAC_SUBNETS=()
DISCOVERY_OUTBOUND_SUBNET=()
get_subnets $USER_RESOURCE_GROUP_NAME $USER_VNET_NAME "default" "28" "17"

###################### Check If NAC_RESOURCE_GROUP_NAME is Exist ##############################################
NAC_RESOURCE_GROUP_NAME_STATUS=`az group exists -n ${NAC_RESOURCE_GROUP_NAME} --subscription ${AZURE_SUBSCRIPTION_ID} 2> /dev/null`
if [ "$NAC_RESOURCE_GROUP_NAME_STATUS" = "true" ]; then
   echo "INFO ::: Provided Azure NAC Resource Group Name is Already Exist : $NAC_RESOURCE_GROUP_NAME"
   exit 1
fi
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
# move config. dat to nasuni-azure-analyticsconnector
cp $CONFIG_DAT_FILE_NAME $GIT_REPO_NAME
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

NAC_TFVARS_FILE_NAME="NAC.tfvars"
rm -rf "$NAC_TFVARS_FILE_NAME"
echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$NAC_TFVARS_FILE_NAME
echo "acs_admin_app_config_name="\"$ACS_ADMIN_APP_CONFIG_NAME\" >>$NAC_TFVARS_FILE_NAME
echo "web_access_appliance_address="\"$WEB_ACCESS_APPLIANCE_ADDRESS\" >>$NAC_TFVARS_FILE_NAME
if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
	echo "user_resource_group_name="\"$USER_RESOURCE_GROUP_NAME\" >>$NAC_TFVARS_FILE_NAME
    echo "user_vnet_name="\"$USER_VNET_NAME\" >>$NAC_TFVARS_FILE_NAME
    echo "user_subnet_name="\"$USER_SUBNET_NAME\" >>$NAC_TFVARS_FILE_NAME
    echo "use_private_acs="\"$USE_PRIVATE_IP\" >>$NAC_TFVARS_FILE_NAME
    echo "nac_subnet="$NAC_SUBNETS >>$NAC_TFVARS_FILE_NAME
    echo "discovery_outbound_subnet="$DISCOVERY_OUTBOUND_SUBNET >>$NAC_TFVARS_FILE_NAME
fi
echo "" >>$NAC_TFVARS_FILE_NAME
echo "" >>$NAC_TFVARS_FILE_NAME
sudo chmod -R 777 $NAC_TFVARS_FILE_NAME

### Check if Resource Group is already provisioned
AZURE_SUBSCRIPTION_ID=$(echo "$AZURE_SUBSCRIPTION_ID" | xargs)

if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
    ### Create the Azure Discovery Function DNS Zone
    create_azure_function_private_dns_zone $USER_RESOURCE_GROUP_NAME $USER_VNET_NAME

    ### Create the Storage Account DNS Zone
    create_storage_account_private_dns_zone $USER_RESOURCE_GROUP_NAME $USER_VNET_NAME
fi

import_configuration(){
    ### Import Configurations details if exist
    INDEX_ENDPOINT_KEY="index-endpoint"
    INDEX_ENDPOINT_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key $INDEX_ENDPOINT_KEY --label $INDEX_ENDPOINT_KEY --query value --output tsv 2> /dev/null`
    if [ "$INDEX_ENDPOINT_APP_CONFIG_STATUS" != "" ]; then
        echo "INFO ::: index-endpoint already exist in the App Config. Importing the existing index-endpoint. "
        COMMAND="terraform import -var-file=$NAC_TFVARS_FILE_NAME azurerm_app_configuration_key.$INDEX_ENDPOINT_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_ADMIN_APP_CONFIG_NAME/AppConfigurationKey/$INDEX_ENDPOINT_KEY/Label/$INDEX_ENDPOINT_KEY"
        $COMMAND
    else
        echo "INFO ::: $INDEX_ENDPOINT_KEY does not exist. It will provision a new $INDEX_ENDPOINT_KEY."
    fi

    WEB_ACCESS_APPLIANCE_ADDRESS_KEY="web-access-appliance-address"
    WEB_ACCESS_APPLIANCE_ADDRESS_KEY_APP_CONFIG_STATUS=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key $WEB_ACCESS_APPLIANCE_ADDRESS_KEY --label $WEB_ACCESS_APPLIANCE_ADDRESS_KEY --query value --output tsv 2> /dev/null`
    if [ "$WEB_ACCESS_APPLIANCE_ADDRESS_KEY_APP_CONFIG_STATUS" != "" ]; then
        echo "INFO ::: web-access-appliance-address already exist in the App Config. Importing the existing web-access-appliance-address. "
        COMMAND="terraform import -var-file=$NAC_TFVARS_FILE_NAME azurerm_app_configuration_key.$WEB_ACCESS_APPLIANCE_ADDRESS_KEY /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_ADMIN_APP_CONFIG_NAME/AppConfigurationKey/$WEB_ACCESS_APPLIANCE_ADDRESS_KEY/Label/$WEB_ACCESS_APPLIANCE_ADDRESS_KEY"
        $COMMAND
    else
        echo "INFO ::: $WEB_ACCESS_APPLIANCE_ADDRESS_KEY does not exist. It will provision a new $WEB_ACCESS_APPLIANCE_ADDRESS_KEY."
    fi
}

import_configuration

echo $JSON_FILE_PATH
LATEST_TOC_HANDLE=""
if [ -f "$JSON_FILE_PATH" ] ; then
	TRACEPATH="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	echo $TRACEPATH
	TRACKER_JSON=$(cat $JSON_FILE_PATH)
	echo "Tracker json" $TRACKER_JSON
	LATEST_TOC_HANDLE=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
	if [ "$LATEST_TOC_HANDLE" =  "null" ] ; then
		LATEST_TOC_HANDLE="null"
	fi
	echo "LATEST_TOC_HANDLE: $LATEST_TOC_HANDLE"
else
	LATEST_TOC_HANDLE=""
	echo "ERROR:::Tracker JSON folder Not present"
fi

echo "INFO ::: LATEST_TOC_HANDLE" $LATEST_TOC_HANDLE
LATEST_TOC_HANDLE_PROCESSED=$LATEST_TOC_HANDLE

FOLDER_PATH=`pwd`

##appending latest_toc_handle_processed to TFVARS_FILE
echo "PrevUniFSTOCHandle="\"$LATEST_TOC_HANDLE\" >>$FOLDER_PATH/$TFVARS_FILE
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "
COMMAND="terraform apply -var-file=$NAC_TFVARS_FILE_NAME -auto-approve"
$COMMAND

####################### 2nd Run for Tracker_UI #########################
if [ $? -eq 0 ]; then
	echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
	echo "NAC_Activity : Export Completed. Indexing in Progress"
	CURRENT_STATE="Export-completed-And-Indexing-In-progress"
	# LATEST_TOC_HANDLE_PROCESSED=$(terraform output -raw latest_toc_handle_processed)
    LATEST_TOC_HANDLE_PROCESSED=$UNIFS_TOC_HANDLE
	echo "INFO ::: LATEST_TOC_HANDLE_PROCESSED for NAC Discovery is : $LATEST_TOC_HANDLE_PROCESSED"
	generate_tracker_json $ACS_URL $ACS_REQUEST_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
    append_nmc_details_to_config_dat $UNIFS_TOC_HANDLE $SOURCE_CONTAINER $SOURCE_CONTAINER_SAS_URL $LATEST_TOC_HANDLE_PROCESSED
else
	echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
	echo "NAC_Activity : Export Failed/Indexing Failed"
 	CURRENT_STATE="Export-Failed-And-Indexing-Failed"
	generate_tracker_json $ACS_URL $ACS_REQUEST_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	##exit 1
fi

echo "NAC_Activity : Indexing Completed"
MOST_RECENT_RUN=$(date "+%Y:%m:%d-%H:%M:%S")
CURRENT_STATE="Indexing-Completed"

generate_tracker_json $ACS_URL $ACS_REQUEST_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
append_nmc_details_to_config_dat $UNIFS_TOC_HANDLE $SOURCE_CONTAINER $SOURCE_CONTAINER_SAS_URL $LATEST_TOC_HANDLE_PROCESSED
#################### 2nd Run for Tracker_UI Complete##########################


if [ $? -eq 0 ]; then 
    add_metadat_to_destination_blob $DESTINATION_CONTAINER_NAME $DESTINATION_CONTAINER_SAS_URL $NMC_VOLUME_NAME $UNIFS_TOC_HANDLE
    echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
else
    echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
    exit 1
fi

##################################### END NAC Provisioning ###################################################################
##################################### Blob Store Cleanup START #####################################################################
ACS_SERVICE_NAME=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key acs-service-name --label acs-service-name --query value --output tsv 2> /dev/null`
echo "INFO ::: ACS Service Name : $ACS_SERVICE_NAME"

ACS_API_KEY=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key acs-api-key --label acs-api-key --query value --output tsv 2> /dev/null`
echo "INFO ::: ACS Service API Key : $ACS_API_KEY"

run_cognitive_search_indexer $ACS_SERVICE_NAME $ACS_API_KEY

destination_blob_cleanup $DESTINATION_CONTAINER_NAME $DESTINATION_CONTAINER_SAS_URL $ACS_SERVICE_NAME $ACS_API_KEY $USE_PRIVATE_IP

cd ..
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
)2>&1 | tee $LOG_FILE

