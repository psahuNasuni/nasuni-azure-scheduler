#!/bin/bash
##############################################
## Pre-Requisite(S):						##
## 		- Git, AZURE CLI, JQ 				##
##		- AZURE Subscription				##
##############################################
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
START=$(date +%s)
LOG_FILE=NAC_SCHEDULER_$DATE_WITH_TIME.log
(

get_destination_container_url(){
	DESTINATION_CONTAINER_URL=$1
	EDGEAPPLIANCE_RESOURCE_GROUP=$2
	### DESTINATION_BUCKET_URL="https://destinationbktsa.blob.core.windows.net/destinationbkt" ## "From_Key_Vault"
	DESTINATION_CONTAINER_NAME=$(echo ${DESTINATION_CONTAINER_URL} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	### https://destinationbktsa.blob.core.windows.net/destinationbkt From this we can get DESTINATION_STORAGE_ACCOUNT_NAME=destinationbktsa and DESTINATION_BUCKET_NAME=destinationbkt  and DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=az storage account show-connection-string --name nmcfilersa
	DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_URL} | cut -d/ -f3-|cut -d'.' -f1) #"destinationbktsa"
	### Destination account-key: 
	DESTINATION_ACCOUNT_KEY=`az storage account keys list --account-name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.[0].value'`
	DESTINATION_CONTAINER_TOCKEN=`az storage account generate-sas --expiry ${SAS_EXPIRY} --permissions wdl --resource-types co --services b --account-key ${DESTINATION_ACCOUNT_KEY} --account-name ${DESTINATION_STORAGE_ACCOUNT_NAME} --https-only`
	DESTINATION_CONTAINER_TOCKEN=$(echo "$DESTINATION_CONTAINER_TOCKEN" | tr -d \")
	DESTINATION_CONTAINER_SAS_URL="https://$DESTINATION_STORAGE_ACCOUNT_NAME.blob.core.windows.net/?$DESTINATION_CONTAINER_TOCKEN"

	DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=`az storage account show-connection-string -g $EDGEAPPLIANCE_RESOURCE_GROUP --name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.connectionString'`
	echo "INFO ::: SUCCESS :: Get destination container url."

}

check_if_VNET_exists(){
	INPUT_VNET="$1"
	NETWORKING_RESOURCE_GROUP="$2"

	VNET_CHECK=`az network vnet show --name $INPUT_VNET --resource-group $NETWORKING_RESOURCE_GROUP | jq -r .provisioningState`
	if [ "$VNET_CHECK" == "Succeeded" ]; then
		echo "INFO ::: VNET $INPUT_VNET is Valid" 
	else
		echo "ERROR ::: VNET $INPUT_VNET not available. Please provide a valid VNET NAME."
		exit 1
	fi

	#VNET_0_SUBNET=`az network vnet show --name $INPUT_VNET --resource-group $NETWORKING_RESOURCE_GROUP | jq -r .subnets[0].name`
	SUBNET_0_NAME="$INPUT_VNET-0-subnet"
	SUBNET_CHECK=`az network vnet subnet show --name $SUBNET_0_NAME --vnet-name $INPUT_VNET --resource-group $NETWORKING_RESOURCE_GROUP | jq -r .provisioningState`
	if [ "$SUBNET_CHECK" != "Succeeded" ]; then
		echo "INFO ::: SUBNET $SUBNET_0_NAME is not EXIST should be created New..."
		echo "INFO ::: Creating Subnet $SUBNET_0_NAME ::: STARTED"
		
		get_subnets $NETWORKING_RESOURCE_GROUP $INPUT_VNET "24" "1"
		VNET_0_SUBNET_CIDR=$(echo "$SUBNETS_CIDR" | sed 's/[][]//g' | tr -d '"')
		echo "VNET_0_SUBNET_CIDR: $VNET_0_SUBNET_CIDR----------------"
		VNET_0_SUBNET=$(az network vnet subnet create -n $SUBNET_0_NAME --vnet-name $INPUT_VNET -g $NETWORKING_RESOURCE_GROUP --service-endpoints "Microsoft.Web" "Microsoft.Storage" --address-prefixes "$VNET_0_SUBNET_CIDR")

		SUBNET_STATUS_CHECK=`az network vnet subnet show --name $SUBNET_0_NAME --vnet-name $INPUT_VNET --resource-group $NETWORKING_RESOURCE_GROUP | jq -r .provisioningState`
		if [ "$SUBNET_STATUS_CHECK" != "Succeeded" ]; then
			echo "ERROR ::: SUBNET $SUBNET_0_NAME Creation Failed."
			exit 1
		else
			echo "INFO ::: SUBNET $SUBNET_0_NAME is Created."
		fi
		
		echo "INFO ::: Creating Subnet $SUBNET_0_NAME ::: COMPLETED"
	else
		echo "INFO ::: SUBNET $SUBNET_0_NAME is Already EXIST"
	fi

	SUBNET_NAME="$SUBNET_0_NAME"
	echo "SUBNET_NAME=$SUBNET_0_NAME , USER_VNET_NAME=$INPUT_VNET"
	
}

check_if_pem_file_exists() {
	FILE=$(echo "$1" | tr -d '"')
	if [ -f "$FILE" ]; then
		echo "INFO ::: $FILE exists."
	else 
		echo "ERROR ::: $FILE does not exist."
		exit 1
	fi
}

validate_github() {
	GITHUB_ORGANIZATION=$1
	REPO_FOLDER=$2
	if [ "$GITHUB_ORGANIZATION" != "" ]; then
		echo "INFO ::: Value of github_organization is $GITHUB_ORGANIZATION"	
	else 
		GITHUB_ORGANIZATION="nasuni-labs"
		echo "INFO ::: Value of github_organization is set to default as $GITHUB_ORGANIZATION"	
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

feed_config_Data_default_values() {
	CONFIG_DAT_FILE_NAME="$1"
	KEY="$2"
	STARTINGPOINT="/"
	INCLUDEFILTERPATTERN='*'
	INCLUDEFILTERTYPE="glob"
	EXCLUDEFILTERPATTERN="null"
	EXCLUDEFILTERTYPE="glob"
	MINFILESIZEFILTER="0b"
	MAXFILESIZEFILTER="5gb"
	EXCLUDETEMPFILES='True'
	case "$KEY" in
		"StartingPoint") VAL=$STARTINGPOINT 
		;;
		"IncludeFilterPattern") VAL=\'$INCLUDEFILTERPATTERN\'
		;;
		"IncludeFilterType") VAL=$INCLUDEFILTERTYPE 
		;;
		"ExcludeFilterPattern") VAL=$EXCLUDEFILTERPATTERN 
		;;
		"ExcludeFilterType") VAL=$EXCLUDEFILTERTYPE 
		;;
		"MinFileSizeFilter") VAL=$MINFILESIZEFILTER 
		;;
		"MaxFileSizeFilter") VAL=$MAXFILESIZEFILTER 
		;;
		"ExcludeTempFiles") VAL=\'$EXCLUDETEMPFILES\' 
		;;
	esac
echo "$KEY: "$VAL >>$CONFIG_DAT_FILE_NAME
}

feed_config_Data_user_overridden_values() {
    CONFIG_DAT_FILE_NAME="$1"
    KEY="$2"
    VALUE="$3"
    echo "$KEY: "$VALUE >>$CONFIG_DAT_FILE_NAME
}

feed_config_Data_user() {
    CONFIG_DAT_FILE_NAME="config.dat"
    st_array=(StartingPoint IncludeFilterPattern IncludeFilterType ExcludeFilterPattern ExcludeFilterType MinFileSizeFilter MaxFileSizeFilter MaxInvocations ExcludeTempFiles)
    for key in "${st_array[@]}"
    do
        feed_config_Data_default_values $CONFIG_DAT_FILE_NAME $key 
    done
    
}

append_nac_static_values_to_config_dat() {
	NAC_INPUT_KVP_FILE="$1"
	CONFIG_DAT_FILE_NAME="$2"
	st_array=(StartingPoint IncludeFilterPattern IncludeFilterType ExcludeFilterPattern ExcludeFilterType MinFileSizeFilter MaxFileSizeFilter MaxInvocations ExcludeTempFiles)
	if [ -f $NAC_INPUT_KVP_FILE ]; then
		echo "INFO ::: KVP file $NAC_INPUT_KVP_FILE is Provided as 5th argument. Appending the Overriding parameters values !!!!" 
		dos2unix $NAC_INPUT_KVP_FILE
		input_items_array=()
		needful_items_array=()
		i=0
		while IFS="=" read -r key value; do
			inarray=$(echo ${st_array[@]} | grep -ow "$key" | wc -w)
			if [ ${#key} -ne 0 ]; then
				if [ $inarray -ne 0 ];then # zero value indicates a match was found
					input_items_array[$i]=${key}
					VAL=""
					VAL=`echo $value | tr -d '"'`
					echo "INFO ::: KEY Provided in 5th params KVP file = $key , VALUE = $VAL"
					feed_config_Data_user_overridden_values $CONFIG_DAT_FILE_NAME $key $VAL
					let i+=1
				fi
			fi
		done <"$NAC_INPUT_KVP_FILE" 
		for key in "${st_array[@]}"
		do
			ok=$(echo ${input_items_array[@]} | grep -ow "$key" | wc -w)
			if [ $ok -eq 0 ];then 
				echo "INFO ::: KEY Not Provided in 5th params KVP file $key" 
			feed_config_Data_default_values $CONFIG_DAT_FILE_NAME $key 
			fi
		done
	else
		### KVP file as 5th argument Not Provided. Appending all static parameters with default values !!!!" 
		echo "INFO ::: KVP file as 5th argument Not Provided. Appending all static parameters with default values !!!!" 
		feed_config_Data_user
	fi
}

append_nac_keys_values_to_tfvars() {
	inputFile="$1"
	outFile="$2"
	dos2unix $inputFile
	while IFS="=" read -r key value; do
		echo "$key ::: $value "
		if [ ${#key} -ne 0 ]; then
			echo "$key=$value" >>$outFile
		fi
	done <"$inputFile"
	echo "INFO ::: Append NAC key-value(s) to tfvars, ::: $outFile"
}

check_if_key_vault_exists() {
	AZURE_KEYVAULT_NAME="$1"
	# Verify the Secret Exists in KeyVault
	if [[ "$(az keyvault show --name ${AZURE_KEYVAULT_NAME} | jq -r .properties.provisioningState 2> /dev/null)" == Succeeded ]]; then
		echo "Y"
	else
		echo "N"
	fi
}

validate_kvp() {
	key="$1"
	val="$2"
	if [[ $val == "" ]]; then
		echo "ERROR ::: Empty Value provided. Please provide a valid value for ${key}."
		exit 1
	else
		echo "INFO ::: Value of ${key} is ${val}"
	fi
} 

update_destination_container_url(){
	ACS_ADMIN_APP_CONFIG_NAME="$1"
	ACS_RESOURCE_GROUP="$2"
	DESTINATION_CONTAINER_NAME="$3"
	DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING="$4"

	# COMMAND SAMPLE="az appconfig kv set --endpoint https://nasuni-labs-acs-admin.azconfig.io --key test2 --value red2 --auth-mode login --yes"
	for config_value in destination-container-name datasource-connection-string 
	do
		option="${config_value}" 
		case ${option} in 
		"destination-container-name")
			COMMAND="az appconfig kv set --endpoint https://$ACS_ADMIN_APP_CONFIG_NAME.azconfig.io --key destination-container-name --label destination-container-name --value $DESTINATION_CONTAINER_NAME --auth-mode login --yes"
			$COMMAND
			;; 
		"datasource-connection-string") 
			COMMAND="az appconfig kv set --endpoint https://$ACS_ADMIN_APP_CONFIG_NAME.azconfig.io --key datasource-connection-string --label datasource-connection-string --value $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING --auth-mode login --yes"
			$COMMAND
			;; 
		esac 
	done

	RESULT=$?
	if [ $RESULT -eq 0 ]; then 
		echo "INFO ::: appconfig update SUCCESS"
	else
		echo "INFO ::: appconfig update FAILED"
		exit 1
	fi
}

get_acs_config_values(){
	ACS_ADMIN_APP_CONFIG_NAME=$1
	APP_CONFIG_KEY=$2
	echo "INFO ::: Validating Secret ::: $APP_CONFIG_KEY"
	APP_CONFIG_VALUE=`az appconfig kv show --name $ACS_ADMIN_APP_CONFIG_NAME --key $APP_CONFIG_KEY --label $APP_CONFIG_KEY --query value --output tsv 2> /dev/null`

	if [ -z "$APP_CONFIG_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key vault $APP_CONFIG_KEY = $APP_CONFIG_VALUE in Key Vault $ACS_ADMIN_APP_CONFIG_NAME."
        exit 1
	else
		if [ "$APP_CONFIG_VALUE" == "null" ] ; then
			echo "ERROR ::: Validation FAILED as, Secret $APP_CONFIG_KEY does not exists in Key Vault $ACS_ADMIN_APP_CONFIG_NAME." 
			exit 1
		else
			if [ "$APP_CONFIG_KEY" == "acs-api-key" ]; then
				ACS_API_KEY=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "acs-resource-group" ]; then
				ACS_RESOURCE_GROUP=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "acs-service-name" ]; then
				ACS_SERVICE_NAME=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "index-endpoint" ]; then
				INDEX_ENDPOINT=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "nmc-api-acs-url" ]; then
				NMC_API_ACS_URL=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "web-access-appliance-address" ]; then
				WEB_ACCESS_APPLIANCE_ADDRESS=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "destination-container-name" ]; then
				DESTINATION_CONTAINER_NAME=$APP_CONFIG_VALUE
			elif [ "$APP_CONFIG_KEY" == "datasource-connection-string" ]; then
				DATASOURCE_CONNECTION_STRING=$APP_CONFIG_VALUE
            fi
			echo "INFO ::: Validation SUCCESS, as key $APP_CONFIG_KEY found in App Configuration: $ACS_ADMIN_APP_CONFIG_NAME."
		fi
	fi
	if [ -z "$APP_CONFIG_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key $APP_CONFIG_KEY = $APP_CONFIG_VALUE in secret $APP_CONFIG_KEY."
        exit 1
	fi
}

validate_secret_values() {
	KEY_VAULT_NAME=$1
	SECRET_NAME=$2
	echo "INFO ::: Validating Secret ::: $SECRET_NAME"
	SECRET_VALUE=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$SECRET_NAME" --query value --output tsv 2> /dev/null)

	if [ -z "$SECRET_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key vault $SECRET_NAME = $SECRET_VALUE in Key Vault $KEY_VAULT_NAME."
        exit 1
	else
		if [ "$SECRET_VALUE" == "null" ] ; then
			echo "ERROR ::: Validation FAILED as, Secret $SECRET_NAME does not exists in Key Vault $KEY_VAULT_NAME." 
			exit 1
		else
			if [ "$SECRET_NAME" == "azure-subscription" ]; then
				AZURE_SUBSCRIPTION=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "azure-location" ]; then
				AZURE_LOCATION=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "product-key" ]; then
				PRODUCT_KEY=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nmc-api-username" ]; then
				NMC_API_USERNAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nmc-api-password" ]; then
				NMC_API_PASSWORD=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nmc-api-endpoint" ]; then
				NMC_API_ENDPOINT=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "web-access-appliance-address" ]; then
				WEB_ACCESS_APPLIANCE_ADDRESS=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "use-private-ip" ]; then
				USE_PRIVATE_IP=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "pem-key-path" ]; then
				PEM_KEY_PATH=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "cred-vault" ]; then
				CRED_VAULT=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "sp-secret" ]; then
				SP_SECRET=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "github-organization" ]; then
				GITHUB_ORGANIZATION=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "destination-container-url" ]; then
				DESTINATION_CONTAINER_URL=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "volume-key-container-url" ]; then
				VOLUME_KEY_BLOB_URL=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "edgeappliance-resource-group" ]; then
				EDGEAPPLIANCE_RESOURCE_GROUP=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nac-scheduler-name" ]; then
				NAC_SCHEDULER_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "user-vnet-name" ]; then
				USER_VNET_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "networking-resource-group" ]; then
				NETWORKING_RESOURCE_GROUP=$SECRET_VALUE
            fi
			echo "INFO ::: Validation SUCCESS, as key $SECRET_NAME found in Key Vault $KEY_VAULT_NAME."
		fi
	fi
	if [ -z "$SECRET_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key $SECRET_NAME = $SECRET_VALUE in secret $SECRET_NAME."
        exit 1
	fi
}

### Import ACS App Config 

import_acs_app_config(){
	ACS_ADMIN_APP_CONFIG_NAME="$1"
	ACS_RESOURCE_GROUP="$2"
	ACS_APP_CONFIG_ID="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_ADMIN_APP_CONFIG_NAME"
	COMMAND="terraform import -var-file=$ACS_TFVARS_FILE_NAME azurerm_app_configuration.appconf $ACS_APP_CONFIG_ID"
    $COMMAND
}

create_app_config_private_dns_zone_virtual_network_link(){
	APP_CONFIG_RESOURCE_GROUP="$1"
	APP_CONFIG_VNET_NAME="$2"
	APP_CONFIG_PRIVAE_DNS_ZONE_NAME="privatelink.azconfig.io"
	APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME=`az network private-dns link vnet list -g $APP_CONFIG_RESOURCE_GROUP -z $APP_CONFIG_PRIVAE_DNS_ZONE_NAME | jq '.[]' | jq 'select((.virtualNetwork.id | contains('\"$APP_CONFIG_VNET_NAME\"')) and (.virtualNetwork.resourceGroup='\"$APP_CONFIG_RESOURCE_GROUP\"'))'| jq -r '.name'`
	
	APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS=`az network private-dns link vnet show -g $APP_CONFIG_RESOURCE_GROUP -n $APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME -z $APP_CONFIG_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	
			
		if [ "$APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS" == "Succeeded" ]; then
			echo "INFO ::: Private DNS Zone Virtual Network Link for App Config is already exist."
			
		else
			echo "INFO ::: $APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME dns zone virtual link does not exist. It will provision a new $APP_CONFIG_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME."
			
			VIRTUAL_NETWORK_ID=`az network vnet show -g $APP_CONFIG_RESOURCE_GROUP -n $APP_CONFIG_VNET_NAME --query id --output tsv 2> /dev/null`
			LINK_NAME="nacappconfigvnetlink"
			
			echo "STARTED ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation ::: $LINK_NAME"
			
			APP_CONFIG_DNS_PRIVATE_LINK=`az network private-dns link vnet create -g $APP_CONFIG_RESOURCE_GROUP -n $LINK_NAME -z $APP_CONFIG_PRIVAE_DNS_ZONE_NAME -v $VIRTUAL_NETWORK_ID -e False | jq -r '.provisioningState'`
			if [ "$APP_CONFIG_DNS_PRIVATE_LINK" == "Succeeded" ]; then
				echo "COMPLETED ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone virtual link successfully created ::: $LINK_NAME"
			else
				echo "ERROR ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation failed"
				exit 1
			fi
		fi
}

create_app_config_private_dns_zone(){
	APP_CONFIG_PRIVAE_DNS_ZONE_RESOURCE_GROUP="$1"
	APP_CONFIG_VNET_NAME="$2"
	APP_CONFIG_PRIVAE_DNS_ZONE_NAME="privatelink.azconfig.io"
	APP_CONFIG_PRIVAE_DNS_ZONE_STATUS=`az network private-dns zone show --resource-group $APP_CONFIG_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $APP_CONFIG_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	

		if [ "$APP_CONFIG_PRIVAE_DNS_ZONE_STATUS" == "Succeeded" ]; then
			echo "INFO ::: Private DNS Zone for App Config is already exist."
			
		else
			echo "INFO ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone does not exist. It will create a new $APP_CONFIG_PRIVAE_DNS_ZONE_NAME."
			
			echo "STARTED ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone creation"
			
			APP_CONFIG_DNS_ZONE=`az network private-dns zone create -g $APP_CONFIG_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $APP_CONFIG_PRIVAE_DNS_ZONE_NAME | jq -r '.provisioningState'`
			if [ "$APP_CONFIG_DNS_ZONE" == "Succeeded"  ]; then
				echo "COMPLETED ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone successfully created"
				create_app_config_private_dns_zone_virtual_network_link $APP_CONFIG_PRIVAE_DNS_ZONE_RESOURCE_GROUP $APP_CONFIG_VNET_NAME
			else
				echo "ERROR ::: $APP_CONFIG_PRIVAE_DNS_ZONE_NAME dns zone creation failed"
				exit 1
			fi
		fi
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
		LINK_NAME="nacfunctionvnetlink"
		echo "INFO ::: $LINK_NAME dns zone virtual link does not exist. It will provision a new $LINK_NAME."
		
		VIRTUAL_NETWORK_ID=`az network vnet show -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $AZURE_FUNCTION_VNET_NAME --query id --output tsv 2> /dev/null`
		
		echo "STARTED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation ::: $LINK_NAME"
		
		FUNCTION_APP_DNS_PRIVATE_LINK=`az network private-dns link vnet create -g $AZURE_FUNCTION_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_RESOURCE_GROUP -n $LINK_NAME -z $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME -v $VIRTUAL_NETWORK_ID -e False | jq -r '.provisioningState'`
		if [ "$FUNCTION_APP_DNS_PRIVATE_LINK" == "Succeeded" ]; then
			echo "COMPLETED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link successfully created ::: $LINK_NAME"
		else
			echo "ERROR ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation failed"
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
		
		FUNCTION_APP_DNS_ZONE=`az network private-dns zone create -g $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP -n $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME | jq -r '.provisioningState'`
		if [ "$FUNCTION_APP_DNS_ZONE" == "Succeeded" ]; then
			echo "COMPLETED ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone successfully created"
			create_azure_function_private_dns_zone_virtual_network_link $AZURE_FUNCTION_PRIVAE_DNS_ZONE_RESOURCE_GROUP $AZURE_FUNCTION_VNET_NAME
		else
			echo "ERROR ::: $AZURE_FUNCTION_PRIVAE_DNS_ZONE_NAME dns zone creation failed"
			exit 1
		fi
	fi
}

create_acs_private_dns_zone_virtual_network_link(){
	ACS_DNS_RESOURCE_GROUP="$1"
	ACS_VNET_NAME="$2"
	ACS_PRIVAE_DNS_ZONE_NAME="privatelink.search.windows.net"
	
	ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME=`az network private-dns link vnet list -g $ACS_DNS_RESOURCE_GROUP -z $ACS_PRIVAE_DNS_ZONE_NAME | jq '.[]' | jq 'select((.virtualNetwork.id | contains('\"$ACS_VNET_NAME\"')) and (.virtualNetwork.resourceGroup='\"$ACS_DNS_RESOURCE_GROUP\"'))'| jq -r '.name'`

	ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS=`az network private-dns link vnet show -g $ACS_DNS_RESOURCE_GROUP -n $ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME -z $ACS_PRIVAE_DNS_ZONE_NAME --query provisioningState --output tsv 2> /dev/null`	
			
		if [ "$ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_STATUS" == "Succeeded" ]; then
			echo "INFO ::: Private DNS Zone Virtual Network Link for Azure Cognitive Search is already exist."
			
		else
			echo "INFO ::: $ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME dns zone virtual link does not exist. It will provision a new $ACS_PRIVATE_DNS_ZONE_VIRTUAL_NETWORK_LINK_NAME."
			
			VIRTUAL_NETWORK_ID=`az network vnet show -g $ACS_DNS_RESOURCE_GROUP -n $ACS_VNET_NAME --query id --output tsv 2> /dev/null`
			LINK_NAME="nacacsvnetlink"
			
			echo "STARTED ::: $ACS_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation ::: $LINK_NAME"
			
			ACS_DNS_PRIVATE_LINK=`az network private-dns link vnet create -g $ACS_DNS_RESOURCE_GROUP -n $LINK_NAME -z $ACS_PRIVAE_DNS_ZONE_NAME -v $VIRTUAL_NETWORK_ID -e False | jq -r '.provisioningState'`
			if [ "$ACS_DNS_PRIVATE_LINK" == "Succeeded" ]; then
				echo "COMPLETED ::: $ACS_PRIVAE_DNS_ZONE_NAME dns zone virtual link successfully created ::: $LINK_NAME"
			else
				echo "ERROR ::: $ACS_PRIVAE_DNS_ZONE_NAME dns zone virtual link creation failed"
				exit 1
			fi
		fi
}

create_acs_private_dns_zone(){
	ACS_DNS_ZONE_RESOURCE_GROUP="$1"
	ACS_VNET_NAME="$2"
	PRIVAE_DNS_ZONE_ACS_NAME="privatelink.search.windows.net"
	PRIVAE_DNS_ZONE_ACS_STATUS=`az network private-dns zone show --resource-group $ACS_DNS_ZONE_RESOURCE_GROUP -n $PRIVAE_DNS_ZONE_ACS_NAME --query provisioningState --output tsv 2> /dev/null`	

		if [ "$PRIVAE_DNS_ZONE_ACS_STATUS" == "Succeeded" ]; then
			echo "INFO ::: Private DNS Zone for Azure Cognitive Search is already exist."
		else
			echo "INFO ::: $PRIVAE_DNS_ZONE_ACS_NAME dns zone does not exist. It will create a new $PRIVAE_DNS_ZONE_ACS_NAME."
			
			echo "STARTED ::: $PRIVAE_DNS_ZONE_ACS_NAME dns zone creation"

			ACS_DNS_ZONE=`az network private-dns zone create -g $ACS_DNS_ZONE_RESOURCE_GROUP -n $PRIVAE_DNS_ZONE_ACS_NAME  | jq -r '.provisioningState'`
			if [ "$ACS_DNS_ZONE" == "Succeeded" ]; then
				echo "COMPLETED ::: $PRIVAE_DNS_ZONE_ACS_NAME dns zone successfully created"
				create_acs_private_dns_zone_virtual_network_link $ACS_DNS_ZONE_RESOURCE_GROUP $ACS_VNET_NAME
			else
				cho "ERROR ::: $PRIVAE_DNS_ZONE_ACS_NAME dns zone creation failed"
				exit 1
			fi
		fi
}

import_app_config_endpoint(){
	ACS_ADMIN_APP_CONFIG_NAME="$1"
	APP_CONFIG_ENDPOINT_RESOURCE_GROUP="$2"

	ACS_ADMIN_APP_CONFIG_PRIVAE_ENDPOINT_NAME="${ACS_ADMIN_APP_CONFIG_NAME}_private_endpoint"
	ACS_ADMIN_APP_CONFIG_NAME_PRIVAE_ENDPOINT_STATUS=`az network private-endpoint show --name $ACS_ADMIN_APP_CONFIG_PRIVAE_ENDPOINT_NAME --resource-group $APP_CONFIG_ENDPOINT_RESOURCE_GROUP --query provisioningState --output tsv 2> /dev/null`	
    if [ "$ACS_ADMIN_APP_CONFIG_NAME_PRIVAE_ENDPOINT_STATUS" == "Succeeded" ]; then
        echo "INFO ::: Private endpoint already exist. Importing the existing ACS APP CONFIG Endpoint."
        COMMAND="terraform import -var-file=$ACS_TFVARS_FILE_NAME azurerm_private_endpoint.appconf_private_endpoint[0] /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$APP_CONFIG_ENDPOINT_RESOURCE_GROUP/providers/Microsoft.Network/privateEndpoints/$ACS_ADMIN_APP_CONFIG_PRIVAE_ENDPOINT_NAME"
        $COMMAND
    else
        echo "INFO ::: $ACS_ADMIN_APP_CONFIG_PRIVAE_ENDPOINT_NAME endpoint does not exist. It will provision a new $ACS_ADMIN_APP_CONFIG_PRIVAE_ENDPOINT_NAME."
    fi
}


######################## Validating AZURE Subscription for NAC ####################################
ARG_COUNT="$#"
validate_AZURE_SUBSCRIPTION() {
	echo "INFO ::: Validating AZURE Subscription ${AZURE_SUBSCRIPTION} for NAC . . . . . . . . . !!!"
	AZURE_SUBSCRIPTION_VALUE=`az account show --query "id" -o tsv`
	AZURE_USER_TYPE=`az account show --query user | jq -r .type`
	echo "$AZURE_USER_TYPE"
	echo "$AZURE_SUBSCRIPTION_VALUE"
	if [ "$AZURE_SUBSCRIPTION_VALUE" == "$AZURE_SUBSCRIPTION" ] && [ "$AZURE_USER_TYPE" == servicePrincipal ]; then
		echo "INFO ::: AZURE Subscription ${AZURE_SUBSCRIPTION} does exists and Logged in USER TYPE is ServicePrincipal "
		COMMAND=`az account set --subscription "${AZURE_SUBSCRIPTION}"`
		AZURE_TENANT_ID="$(az account list --query "[?isDefault].tenantId" -o tsv)"
		AZURE_SUBSCRIPTION_ID="$(az account list --query "[?isDefault].id" -o tsv)"
		SP_APPLICATION_ID="$(az account list --query "[?isDefault].user.name" -o tsv)"
	else
		echo "ERROR ::: AZURE Subscription ${AZURE_SUBSCRIPTION} does not exists. or Logged in USER TYPE is not ServicePrincipal . . . . . . . . . !!!"
		echo "To Create AZURE Subscription, Run cli command - az login --service-principal --tenant {TENANT_ID} --username {SP_USERNAME} --password {SP_PASSWORD}"
		exit 1
	fi
	# Setting below values as ENV Variable

	export ARM_CLIENT_ID="$SP_APPLICATION_ID"
	export ARM_CLIENT_SECRET="$SP_SECRET"
	export ARM_TENANT_ID="$AZURE_TENANT_ID"
	export ARM_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID"

	echo "INFO ::: AZURE_TENANT_ID=$AZURE_TENANT_ID"
	echo "INFO ::: AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"
	echo "INFO ::: SP_APPLICATION_ID=$SP_APPLICATION_ID"
	echo "INFO ::: AZURE Subscription Validation SUCCESS !!!"
}

provision_Azure_Cognitive_Search(){
	######################## Check If Azure Cognitice Search Available ###############################################
	#### ACS_SERVICE_NAME : Take it from KeyVault that is creted with ACS
	IS_ACS="$1"
	ACS_RESOURCE_GROUP="$2"
	ACS_ADMIN_APP_CONFIG_NAME="$3"
	IS_ADMIN_VAULT_YN="N"
	IS_ACS_RG_YN="N"
	if [ "$IS_ACS" == "N" ]; then
		echo "INFO ::: Azure Cognitive Search is Not Configured. Need to Provision Azure Cognitive Search Before, NAC Provisioning."
		echo "INFO ::: Begin Azure Cognitive Search Provisioning."
		########## Download CognitiveSearch Provisioning Code from GitHub ##########
		########## GITHUB_ORGANIZATION defaults to nasuni-labs     		  ##########
		REPO_FOLDER="nasuni-azure-cognitive-search"
		validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
		########################### Git Clone  ###############################################################
		echo "INFO ::: BEGIN - Git Clone !!!"
		### Download Provisioning Code from GitHub
		GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/nasuni-\1/' | cut -d "/" -f 2)
		echo "INFO ::: GIT_REPO $GIT_REPO"
		echo "INFO ::: GIT_REPO_NAME $GIT_BRANCH_NAME ::: GIT_BRANCH_NAME $GIT_BRANCH_NAME"
		rm -rf "${GIT_REPO_NAME}"
		pwd
		COMMAND="git clone -q -b $GIT_BRANCH_NAME $GIT_REPO"
		$COMMAND
		RESULT=$?
		if [ $RESULT -eq 0 ]; then
			echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
		else
			echo "INFO ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
			exit 1
		fi
		cd "${GIT_REPO_NAME}"
		### RUN terraform init
		echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform init . . . . . . . . "
		COMMAND="terraform init"
		$COMMAND

		chmod 755 $(pwd)/*
		### Dont Change the sequence of function calls
		echo "ACS_RESOURCE_GROUP $ACS_RESOURCE_GROUP ACS_ADMIN_APP_CONFIG_NAME $ACS_ADMIN_APP_CONFIG_NAME"
		check_if_resourcegroup_exist $ACS_RESOURCE_GROUP $AZURE_SUBSCRIPTION_ID
		echo "INFO ::: CognitiveSearch provisioning ::: FINISH - Executing ::: Terraform init."
		echo "INFO ::: Create TFVARS file for provisioning Cognitive Search"
		ACS_TFVARS_FILE_NAME="ACS.tfvars"
		rm -rf "$ACS_TFVARS_FILE_NAME"
		echo "acs_rg_YN="\"$IS_ACS_RG_YN\" >>$ACS_TFVARS_FILE_NAME
		echo "acs_rg_name="\"$ACS_RESOURCE_GROUP\" >>$ACS_TFVARS_FILE_NAME
		echo "azure_location="\"$AZURE_LOCATION\" >>$ACS_TFVARS_FILE_NAME
		echo "acs_admin_app_config_name="\"$ACS_ADMIN_APP_CONFIG_NAME\" >>$ACS_TFVARS_FILE_NAME
		echo "acs_app_config_YN="\"$IS_ACS_ADMIN_APP_CONFIG\" >>$ACS_TFVARS_FILE_NAME
		echo "datasource_connection_string="\"$DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING\" >>$ACS_TFVARS_FILE_NAME
		echo "destination_container_name="\"$DESTINATION_CONTAINER_NAME\" >>$ACS_TFVARS_FILE_NAME
		echo "sp_application_id="\"$SP_APPLICATION_ID\" >>$ACS_TFVARS_FILE_NAME
		echo "cognitive_search_YN="\"$IS_ACS\" >>$ACS_TFVARS_FILE_NAME
		if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
			echo "use_private_acs="\"$USE_PRIVATE_IP\" >>$ACS_TFVARS_FILE_NAME
			echo "networking_resource_group="\"$NETWORKING_RESOURCE_GROUP\" >>$ACS_TFVARS_FILE_NAME
			if [[ "$USER_VNET_NAME" != "" ]]; then
				echo "user_vnet_name="\"$USER_VNET_NAME\" >>$ACS_TFVARS_FILE_NAME
			fi
			if [[ "$SUBNET_NAME" != "" ]]; then
				echo "user_subnet_name="\"$SUBNET_NAME\" >>$ACS_TFVARS_FILE_NAME
			fi
		fi

		echo "" >>$ACS_TFVARS_FILE_NAME
		if [[ "$IS_ACS_ADMIN_APP_CONFIG" == "Y" ]]; then
			# Import if acs app config is already provisioned.
			import_acs_app_config $ACS_ADMIN_APP_CONFIG_NAME $ACS_RESOURCE_GROUP
		fi

		if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
			create_acs_private_dns_zone $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME
			create_acs_private_dns_zone_virtual_network_link $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME 
			create_app_config_private_dns_zone $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME
			create_app_config_private_dns_zone_virtual_network_link $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME
			create_azure_function_private_dns_zone $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME
			import_app_config_endpoint $ACS_ADMIN_APP_CONFIG_NAME $NETWORKING_RESOURCE_GROUP
		fi

		echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
		
		COMMAND="terraform apply -var-file=ACS.tfvars -auto-approve"
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
		echo "INFO ::: BEGIN ::: NACScheduler Provisioning . . . . . . . . . . . ."
	fi
	##################################### END Azure CognitiveSearch ###################################################################
}

provision_ACS_if_Not_Available(){
	ACS_SERVICE_NAME="$3"
	ACS_ADMIN_APP_CONFIG_NAME="$2"
	ACS_RESOURCE_GROUP="$1"
	echo "INFO ::: Checking for ACS Availability Status . . . . "

	echo "INFO ::: Checking for ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME . . ."
	check_if_acs_app_config_exists $ACS_ADMIN_APP_CONFIG_NAME $ACS_RESOURCE_GROUP
	echo "IS_ACS_ADMIN_APP_CONFIG $IS_ACS_ADMIN_APP_CONFIG"
	
	if [ "$IS_ACS_ADMIN_APP_CONFIG" == "Y" ]; then
		
		### update the Destination bucket connection string in ACS_ADMIN_APP_CONFIG_NAME
		update_destination_container_url $ACS_ADMIN_APP_CONFIG_NAME $ACS_RESOURCE_GROUP $DESTINATION_CONTAINER_NAME $DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING
		get_acs_config_values "$ACS_ADMIN_APP_CONFIG_NAME" acs-service-name

		if [ "$ACS_SERVICE_NAME" == "" ]; then
			### Service Not available in ACS Admin App Configuration 
			############ START : Provision ACS if Not Available ################
			echo "INFO ::: Service $ACS_SERVICE_NAME is Not available in ACS Admin App Configuration "
			provision_Azure_Cognitive_Search "N" $ACS_RESOURCE_GROUP $ACS_ADMIN_APP_CONFIG_NAME
			### SMG ###
			### import acs dns zone, endpoint, virtual_link 
			############ END: Provision ACS if Not Available ################
		else
			### Service available in ACS Admin App Configuration but not in running condition
			echo "INFO ::: Service $ACS_SERVICE_NAME entry found in ACS Admin App Configuration but not in running condition."
			ACS_STATUS=`az search service show --name $ACS_SERVICE_NAME --resource-group $ACS_RESOURCE_GROUP | jq -r .status 2> /dev/null`
			if [ "$ACS_STATUS" == "" ] || [ "$ACS_STATUS" == null ]; then
				############ START : Provision ACS if Not Available ################
				provision_Azure_Cognitive_Search "N" $ACS_RESOURCE_GROUP $ACS_ADMIN_APP_CONFIG_NAME
				############ END: Provision ACS if Not Available ################
			else
				echo "INFO ::: ACS $ACS_SERVICE_NAME Status is: $ACS_STATUS"
			fi
		fi 
	else ## When Key Vault Not Available - 1st Run
		############ START : Provision ACS if Not Available ################	
		provision_Azure_Cognitive_Search "N" $ACS_RESOURCE_GROUP $ACS_ADMIN_APP_CONFIG_NAME
		############ END: Provision ACS if Not Available ################
	fi	
}

check_network_availability(){
	if [ "$NETWORKING_RESOURCE_GROUP" == "" ] || [ "$NETWORKING_RESOURCE_GROUP" == null ]; then
		echo "INFO ::: Azure Virtual Network Resource Group is Not provided."
		exit 1
	else
		### If resource group already available
		echo "INFO ::: Azure Virtual Network Resource Group is provided as $NETWORKING_RESOURCE_GROUP"
	fi
	if [ "$USER_VNET_NAME" == "" ] || [ "$USER_VNET_NAME" == "null" ]; then
		echo "INFO ::: USER_VNET_NAME not provided in the user Secret"  
		exit 1
	else
	### If USER_VNET_NAME provided
		check_if_VNET_exists $USER_VNET_NAME $NETWORKING_RESOURCE_GROUP
	fi
}

check_if_acs_app_config_exists(){
	ACS_ADMIN_APP_CONFIG_NAME="$1"
	ACS_RESOURCE_GROUP="$2"
	echo "INFO ::: Checking for Azure App Configuration $ACS_ADMIN_APP_CONFIG_NAME . . ."
	APP_CONFIG_STATUS=`az appconfig show --name $ACS_ADMIN_APP_CONFIG_NAME --resource-group $ACS_RESOURCE_GROUP --query provisioningState --output tsv 2> /dev/null`
	if [ "$APP_CONFIG_STATUS" == "Succeeded" ]; then
		echo "INFO ::: Azure App Configuration $ACS_ADMIN_APP_CONFIG_NAME is already exist. . "
		IS_ACS_ADMIN_APP_CONFIG="Y"
		ACS_APP_CONFIG_ID="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP/providers/Microsoft.AppConfiguration/configurationStores/$ACS_ADMIN_APP_CONFIG_NAME"
	else
		IS_ACS_ADMIN_APP_CONFIG="N"
		echo "INFO ::: Azure App Configuration $ACS_ADMIN_APP_CONFIG_NAME does not exist. It will provision a new acs-admin-app-config Configuration with ACS Service."
	fi
}

check_if_resourcegroup_exist(){
	ACS_RESOURCE_GROUP="$1"
	AZURE_SUBSCRIPTION_ID="$2"
	### Check if Resource Group is already provisioned
	echo "INFO ::: Check if Resource Group $ACS_RESOURCE_GROUP exist . . . . "
	ACS_RG_STATUS=`az group show --name $ACS_RESOURCE_GROUP --query properties.provisioningState --output tsv 2> /dev/null`
	if [ "$ACS_RG_STATUS" == "Succeeded" ]; then
		pwd
		IS_ACS_RG_YN="Y"
		echo "INFO ::: Azure Cognitive Search Resource Group $ACS_RESOURCE_GROUP is already exist. Importing the existing Resource Group."
		COMMAND="terraform import -var-file=$ACS_TFVARS_FILE_NAME azurerm_resource_group.acs_rg /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$ACS_RESOURCE_GROUP"
		$COMMAND
	else
		IS_ACS_RG_YN="N"
		echo "INFO ::: Cognitive Search Resource Group $ACS_RESOURCE_GROUP does not exist. It will provision a new Resource Group."
	fi
}

get_subnets(){
    NETWORKING_RESOURCE_GROUP="$1"
    USER_VNET_NAME="$2"
    SUBNET_MASK="$3"
	REQUIRED_SUBNET_COUNT="$4"

	DIRECTORY=$(pwd)
	echo "Directory: $DIRECTORY"
	FILENAME="$DIRECTORY/create_subnets/create_subnet_infra.py"
	OUTPUT=$(python3 $FILENAME $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME $SUBNET_MASK $REQUIRED_SUBNET_COUNT 2>&1 >/dev/null > available_subnets.txt)
	COUNTER=0
	SUBNETS_CIDR=(`cat available_subnets.txt`)
	SUBNETS_CIDR=$(echo "$SUBNETS_CIDR" | sed 's/[][]//g')
	echo "Subnet list from file : $SUBNETS_CIDR"
	# Use comma as separator and apply as pattern
}

########################## Create CRON ############################################################
Schedule_CRON_JOB() {
	NAC_SCHEDULER_IP_ADDR=$1
	PEM="$PEM_KEY_PATH"
	check_if_pem_file_exists $PEM
	ls
	echo $PEM
	chmod 400 $PEM
	echo "INFO ::: Public IP Address:- $NAC_SCHEDULER_IP_ADDR"
	echo "ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"
	### Create TFVARS File for PROVISION_NAC.SH which is Used by CRON JOB - to Provision NAC Stack
	CONFIG_DAT_FILE_NAME="config.dat"
	rm -rf "$CONFIG_DAT_FILE_NAME"
	AZURE_CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName)
	NEW_NAC_IP=$(echo $NAC_SCHEDULER_IP_ADDR | tr '.' '-')
	RND=$(( $RANDOM % 1000000 )); 
	### Pass below 3 parameters as Blank values to Provision_nac.sh. 
	UNIFS_TOC_HANDLE=""
	SOURCE_CONTAINER=""
	SOURCE_CONTAINER_SAS_URL=""
	VOLUME_KEY_BLOB_SAS_URL=""
    ### Generating NAC Resource group name dynamically
    NAC_RESOURCE_GROUP_NAME="nac-resource-group-$RND"
    echo "Name: "$NAC_RESOURCE_GROUP_NAME >>$CONFIG_DAT_FILE_NAME
	### AzureSubscriptionID >>>>> Read from user_secret Key Vault
    echo "AzureSubscriptionID: "$AZURE_SUBSCRIPTION_ID >>$CONFIG_DAT_FILE_NAME
	### AzureLocation >>>>> Read from user_secret Key Vault
    echo "AzureLocation: "$(echo "$AZURE_LOCATION" | tr '[:upper:]' '[:lower:]' | tr -d ' ' )>>$CONFIG_DAT_FILE_NAME
	### ProductKey >>>>> Read from user_secret Key Vault
    echo "ProductKey: "$PRODUCT_KEY>>$CONFIG_DAT_FILE_NAME
	### VolumeKeyPassphrase >>>>> Recommended as 'null' for AZURE NAC
    echo "VolumeKeyPassphrase: "\'null\' >>$CONFIG_DAT_FILE_NAME
	### PrevUniFSTOCHandle >>>>> will be taken from TrackerJSON. Currently taking as 'null' for AZURE NAC
    echo "PrevUniFSTOCHandle: "null >>$CONFIG_DAT_FILE_NAME
	if [ $ARG_COUNT -eq 5 ]; then
		echo "INFO ::: $ARG_COUNT th Argument is supplied as ::: $NAC_INPUT_KVP"
		### Appending Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
		append_nac_static_values_to_config_dat $NAC_INPUT_KVP $CONFIG_DAT_FILE_NAME
	else
		append_nac_static_values_to_config_dat "4_Arguments_Passed" $CONFIG_DAT_FILE_NAME
	fi
    echo "DestinationContainer: "$DESTINATION_CONTAINER_NAME >>$CONFIG_DAT_FILE_NAME
    echo "DestinationContainerSASURL: "$DESTINATION_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE_NAME
	echo "UniFSTOCHandle: "$UNIFS_TOC_HANDLE >>$CONFIG_DAT_FILE_NAME
	echo "SourceContainer: "$SOURCE_CONTAINER >>$CONFIG_DAT_FILE_NAME
	echo "SourceContainerSASURL: "$SOURCE_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE_NAME
	echo "VolumeKeySASURL: "$VOLUME_KEY_BLOB_SAS_URL>>$CONFIG_DAT_FILE_NAME
	echo "vnetSubscriptionId: "$AZURE_SUBSCRIPTION_ID >>$CONFIG_DAT_FILE_NAME
	echo "vnetResourceGroup: "$NETWORKING_RESOURCE_GROUP >>$CONFIG_DAT_FILE_NAME
	echo "vnetName: "$USER_VNET_NAME >>$CONFIG_DAT_FILE_NAME

    chmod 777 $CONFIG_DAT_FILE_NAME

	CRON_DIR_NAME="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	
	NAC_TXT_FILE_NAME="NAC.txt"
	rm -rf "$NAC_TXT_FILE_NAME"
	# ACS_RESOURCE_GROUP=$($ACS_RESOURCE_GROUP | tr -d '"')
	# ACS_ADMIN_APP_CONFIG_NAME=$($ACS_ADMIN_APP_CONFIG_NAME | tr -d '"')
	echo "acs_resource_group="$ACS_RESOURCE_GROUP >>$NAC_TXT_FILE_NAME
	echo "azure_location="$AZURE_LOCATION >>$NAC_TXT_FILE_NAME
    echo "acs_admin_app_config_name="$ACS_ADMIN_APP_CONFIG_NAME >>$NAC_TXT_FILE_NAME
	echo "web_access_appliance_address="$WEB_ACCESS_APPLIANCE_ADDRESS >>$NAC_TXT_FILE_NAME
	echo "nmc_volume_name="$NMC_VOLUME_NAME >>$NAC_TXT_FILE_NAME
	echo "github_organization="$GITHUB_ORGANIZATION >>$NAC_TXT_FILE_NAME
	echo "user_secret="$KEY_VAULT_NAME >>$NAC_TXT_FILE_NAME
	echo "sp_application_id="$SP_APPLICATION_ID >>$NAC_TXT_FILE_NAME
	echo "sp_secret="$SP_SECRET >>$NAC_TXT_FILE_NAME
	echo "azure_tenant_id="$AZURE_TENANT_ID >>$NAC_TXT_FILE_NAME
	echo "volume_key_blob_url="$VOLUME_KEY_BLOB_URL >>$NAC_TXT_FILE_NAME
	echo "cred_vault="$CRED_VAULT >>$NAC_TXT_FILE_NAME
	echo "analytic_service="$ANALYTICS_SERVICE >>$NAC_TXT_FILE_NAME
	echo "frequency="$FREQUENCY >>$NAC_TXT_FILE_NAME
	echo "nac_scheduler_name="$NAC_SCHEDULER_NAME >>$NAC_TXT_FILE_NAME
	if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
		echo "use_private_ip="$USE_PRIVATE_IP >>$NAC_TXT_FILE_NAME
		echo "user_subnet_name="$SUBNET_NAME >>$NAC_TXT_FILE_NAME	
	else
		echo "use_private_ip="N >>$NAC_TXT_FILE_NAME
	fi
	
	chmod 777 $NAC_TXT_FILE_NAME

	### Create File to transfer data related to NMC 
	NMC_DETAILS_TXT="nmc_details.txt"
	if [ -f $NMC_DETAILS_TXT ] && [ -s $NMC_DETAILS_TXT ]; then
	> $NMC_DETAILS_TXT
	fi
	echo "nmc_api_endpoint="$NMC_API_ENDPOINT >>$NMC_DETAILS_TXT
	echo "nmc_api_username="$NMC_API_USERNAME >>$NMC_DETAILS_TXT
	echo "nmc_api_password="$NMC_API_PASSWORD >>$NMC_DETAILS_TXT
	echo "nmc_volume_name="$NMC_VOLUME_NAME >>$NMC_DETAILS_TXT
	echo "web_access_appliance_address="$WEB_ACCESS_APPLIANCE_ADDRESS >>$NMC_DETAILS_TXT
	echo "" >>$NMC_DETAILS_TXT
	chmod 777 $NMC_DETAILS_TXT

	
	NMC_DETAILS_JSON="nmc_details.json"

	if [ -f $NMC_DETAILS_JSON ] && [ -s $NMC_DETAILS_JSON ]; then
	> $NMC_DETAILS_JSON
	fi

	echo '{"nmc_api_endpoint":"'$NMC_API_ENDPOINT'",' >>$NMC_DETAILS_JSON
	echo '"nmc_volume_name":"'$NMC_VOLUME_NAME'",' >>$NMC_DETAILS_JSON
	echo '"web_access_appliance_address":"'$WEB_ACCESS_APPLIANCE_ADDRESS'"}' >>$NMC_DETAILS_JSON
	echo "" >>$NMC_DETAILS_JSON
	chmod 777 $NMC_DETAILS_JSON

	JSON_FILE_PATH="/var/www/Tracker_UI/docs/"
	### Create Directory for each Volume
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "[ ! -d $CRON_DIR_NAME ] && mkdir $CRON_DIR_NAME "
	echo "Creating $JSON_FILE_PATH Directory"
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "sudo mkdir -p $JSON_FILE_PATH"
	echo "$JSON_FILE_PATH Directory Created"

	###Moving nmc_detail file to /var/www/
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "sudo mkdir -p /var/www/SearchUI_Web"
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "sudo chmod 777 /var/www/SearchUI_Web"
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "$NMC_DETAILS_JSON"  ubuntu@$NAC_SCHEDULER_IP_ADDR:/var/www/SearchUI_Web

	### Copy TFVARS and provision_nac.sh to NACScheduler
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null provision_nac.sh fetch_volume_data_from_nmc_api.py create_subnets/create_subnet_infra.py tracker_json.py "$NMC_DETAILS_TXT" "$NAC_TXT_FILE_NAME" "$CONFIG_DAT_FILE_NAME" ubuntu@$NAC_SCHEDULER_IP_ADDR:~/$CRON_DIR_NAME
	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to Copy $TFVARS_FILE_NAME to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO ::: $TFVARS_FILE_NAME Uploaded Successfully to NAC_Scheduer Instance."
	fi
	rm -rf $TFVARS_FILE_NAME
	echo "Copying file tracker_json.py $JSON_FILE_PATH Creating Direcotory "
	#dos2unix command execute
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "dos2unix ~/$CRON_DIR_NAME/provision_nac.sh"
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "sudo cp ~/$CRON_DIR_NAME/tracker_json.py $JSON_FILE_PATH"
	### Check If CRON JOB is running for a specific VOLUME_NAME
	echo "Copy completed file tracker_json.py $JSON_FILE_PATH Creating Direcotory  *****************"
	CRON_VOL=$(ssh -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ubuntu@"$NAC_SCHEDULER_IP_ADDR" "crontab -l | grep \"~/$CRON_DIR_NAME/$TFVARS_FILE_NAME\"")
	if [ "$CRON_VOL" != "" ]; then
		### DO Nothing. CRON JOB takes care of NAC Provisioning
		echo "INFO ::: crontab does not require volume entry.As it is already present.:::::"
	else
		### Set up a new CRON JOB for NAC Provisioning
		echo "INFO ::: Setting CRON JOB for $CRON_DIR_NAME as it is not present"
		# ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "(crontab -l ; echo '*/$FREQUENCY * * * * cd ~/$CRON_DIR_NAME && /bin/bash provision_nac.sh  ~/$CRON_DIR_NAME/$TFVARS_FILE_NAME >> ~/$CRON_DIR_NAME/CRON_log-$CRON_DIR_NAME-$DATE_WITH_TIME.log 2>&1') | sort - | uniq - | crontab -"
		ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "(crontab -l ; echo '*/$FREQUENCY * * * * cd ~/$CRON_DIR_NAME && /bin/bash provision_nac.sh  ~/$CRON_DIR_NAME/$TFVARS_FILE_NAME') | sort - | uniq - | crontab -"
		if [ $? -eq 0 ]; then
			echo "INFO ::: CRON JOB Scheduled for NMC VOLUME and Service :: $CRON_DIR_NAME"
			exit 0
		else
			echo "ERROR ::: FAILED to Schedule CRON JOB for NMC VOLUME and Service :: $CRON_DIR_NAME"
			exit 1
		fi
	fi

}
######################################### START : SCRIPT EXECUTION #############################

if [ $# -eq 0 ]; then
	echo "ERROR ::: No argument(s) supplied. This Script Takes 4 Mandatory Arguments 1) NMC Volume_Name, 2) Service, 3) Frequency and 4) User Secret(either Existing Secret Name Or Secret KVPs in a text file)"
	exit 1
elif [ $# -lt 4 ]; then
	echo "ERROR ::: $# argument(s) supplied. This Script Takes 4 Mandatory Arguments 1) NMC Volume_Name, 2) Service, 3) Frequency and 4) User Secret(either Existing Secret Name Or Secret KVPs in a text file)"
	exit 1
fi

#################### Validate Arguments Passed to NAC_Scheduler.sh ####################
NMC_VOLUME_NAME="$1"   ### 1st argument  ::: NMC_VOLUME_NAME
ANALYTICS_SERVICE="$2" ### 2nd argument  ::: ANALYTICS_SERVICE
FREQUENCY="$3"         ### 3rd argument  ::: FREQUENCY
FOURTH_ARG="$4"        ### 4th argument  ::: User Secret a KVP file Or an existing Secret
NAC_INPUT_KVP="$5"     ### 5th argument  ::: User defined KVP file for passing arguments to NAC
SAS_EXPIRY=`date -u -d "1440 minutes" '+%Y-%m-%dT%H:%MZ'`
GIT_BRANCH_NAME="nac_v1.0.7.dev6"
if [[ $GIT_BRANCH_NAME == "" ]]; then
    GIT_BRANCH_NAME="main"
fi
SP_APPLICATION_ID=""

echo "INFO ::: Validating Arguments Passed to NAC_Scheduler.sh"
if [ "${#NMC_VOLUME_NAME}" -lt 3 ]; then
	echo "ERROR ::: Something went wrong. Please re-check 1st argument and provide a valid NMC Volume Name."
	exit 1
fi
if [[ "${#ANALYTICS_SERVICE}" -lt 2 ]]; then
	echo "INFO ::: The length of Service name provided as 2nd argument is too small, So, It will consider ES as the default Analytics Service."
	ANALYTICS_SERVICE="ACS" ### Azure Cognitive Search Service as default
fi
if [[ "${#FREQUENCY}" -lt 2 ]]; then
	echo "ERROR ::: Mandatory 3rd argument is invalid"
	exit 1
else
	REX="^[0-9]+([.][0-9]+)?$"
	if ! [[ $FREQUENCY =~ $REX ]]; then
		echo "ERROR ::: the 3rd Argument is Not a number" >&2
		exit 1
	fi
fi

########## Check If fourth argument is provided
USER_SECRET_EXISTS="N"
if [[ -n "$FOURTH_ARG" ]]; then
	####  Fourth Argument is passed by User as a KeyVault Name
	echo "INFO ::: Fourth Argument $FOURTH_ARG is passed as Azure Key Vault Name"
	AZURE_KEYVAULT_NAME="$FOURTH_ARG"

	### Verify the KeyVault Exists
	AZURE_KEYVAULT_EXISTS=$(check_if_key_vault_exists $AZURE_KEYVAULT_NAME)
	echo "INFO ::: User secret Exists:: $AZURE_KEYVAULT_EXISTS"
	if [ "$AZURE_KEYVAULT_EXISTS" == "Y" ]; then
		### Validate Keys in the Secret
		echo "INFO ::: Check if all Keys are provided"
		validate_secret_values "$AZURE_KEYVAULT_NAME" azure-subscription
		validate_secret_values "$AZURE_KEYVAULT_NAME" azure-location
		validate_secret_values "$AZURE_KEYVAULT_NAME" product-key
		validate_secret_values "$AZURE_KEYVAULT_NAME" web-access-appliance-address
		validate_secret_values "$AZURE_KEYVAULT_NAME" pem-key-path
		validate_secret_values "$AZURE_KEYVAULT_NAME" cred-vault
		validate_secret_values "$AZURE_KEYVAULT_NAME" sp-secret
		validate_secret_values "$AZURE_KEYVAULT_NAME" github-organization
		validate_secret_values "$AZURE_KEYVAULT_NAME" destination-container-url
		validate_secret_values "$AZURE_KEYVAULT_NAME" volume-key-container-url
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-endpoint
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-username
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-password
		validate_secret_values "$AZURE_KEYVAULT_NAME" nac-scheduler-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" edgeappliance-resource-group
		validate_secret_values "$AZURE_KEYVAULT_NAME" user-vnet-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" use-private-ip
		validate_secret_values "$AZURE_KEYVAULT_NAME" networking-resource-group
		echo "INFO ::: Validation SUCCESS for all mandatory Secret-Keys !!!" 
	else
		echo "INFO ::: The Vault $AZURE_KEYVAULT_NAME not found within subscription !!!"
		exit 1
	fi
else
	echo "INFO ::: Fourth argument is NOT provided, So, It will consider prod/nac/admin as the default key vault."
fi

validate_AZURE_SUBSCRIPTION

ACS_ADMIN_APP_CONFIG_NAME="nasuni-labs-acs-admin"
ACS_RESOURCE_GROUP="nasuni-labs-acs-rg"
IS_ACS_ADMIN_APP_CONFIG="N"

######################  Check : If appconfig is permanently deleted ##############################

APP_CONFIG_PURGE_STATUS=`az appconfig show-deleted --name $ACS_ADMIN_APP_CONFIG_NAME --query purgeProtectionEnabled 2> /dev/null`

if [ "$APP_CONFIG_PURGE_STATUS" == "false" ]; then
	echo "INFO ::: ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME is NOT Permanently Deleted ..."
	echo "INFO ::: Permanently Deleting the ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME ..."
	COMMAND="az appconfig purge --name $ACS_ADMIN_APP_CONFIG_NAME -y"
	$COMMAND
elif [ "$APP_CONFIG_PURGE_STATUS" == "true" ]; then
	echo "INFO ::: ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME can NOT be Permanently Deleted ..."
	echo "INFO ::: ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME Purge Protection Enabled was set to TRUE ..."
	exit 1
else
	echo "INFO ::: ACS Admin App Config $ACS_ADMIN_APP_CONFIG_NAME is Already Permanently Deleted ..."
fi

###################################################################################################

ACS_SERVICE_NAME=""

if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
	check_network_availability
fi

DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=""
get_destination_container_url $DESTINATION_CONTAINER_URL $EDGEAPPLIANCE_RESOURCE_GROUP 

provision_ACS_if_Not_Available $ACS_RESOURCE_GROUP $ACS_ADMIN_APP_CONFIG_NAME $ACS_SERVICE_NAME

######################  Check : if NAC Scheduler Instance is Available ##############################
echo "INFO ::: Get IP Address of NAC Scheduler Instance"

### parse_4thArgument_for_nac_KVPs "$FOURTH_ARG"
echo "INFO ::: nac_scheduler_name = $NAC_SCHEDULER_NAME "
if [ "$NAC_SCHEDULER_NAME" != "" ]; then
	### User has provided the NACScheduler Name as Key-Value from 4th Argument
	if [[ "$USE_PRIVATE_IP" != "Y" ]]; then
		### Getting Public_IP of NAC Scheduler
		NAC_SCHEDULER_IP_ADDR=$(az vm list-ip-addresses --name $NAC_SCHEDULER_NAME --resource-group $EDGEAPPLIANCE_RESOURCE_GROUP --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
		echo "INFO ::: Public_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
	else
		### Getting Private_IP of NAC Scheduler
		echo "INFO ::: Private_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
		NAC_SCHEDULER_IP_ADDR=`az vm list-ip-addresses --name $NAC_SCHEDULER_NAME --resource-group $EDGEAPPLIANCE_RESOURCE_GROUP --query "[0].virtualMachine.network.privateIpAddresses[0]" | cut -d":" -f 2 | tr -d '"' | tr -d ' '`
	fi
else
	NAC_SCHEDULER_IP_ADDR=$(az vm list-ip-addresses --name NACScheduler --resource-group $EDGEAPPLIANCE_RESOURCE_GROUP --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
fi
echo $PEM_KEY_PATH
AZURE_KEY=$(echo ${PEM_KEY_PATH} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo $AZURE_KEY
PEM="$AZURE_KEY.pem"

echo "INFO ::: NAC_SCHEDULER_IP_ADDR ::: $NAC_SCHEDULER_IP_ADDR"
if [ "$NAC_SCHEDULER_IP_ADDR" != "" ]; then
	echo "INFO ::: NAC Scheduler Instance is Available. IP Address: $NAC_SCHEDULER_IP_ADDR"
	### Copy the Pem Key from provided path to current folder
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	### Call this function to add Local public IP to Network Security Group (NSG rule) of NAC_SCHEDULER IP
	ls
	echo $PEM
	### nmc endpoint accessibility $NAC_SCHEDULER_NAME $NAC_SCHEDULER_IP_ADDR
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR
###################### NAC Scheduler VM Instance is NOT Available ##############################
else
	
	if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
		get_subnets $NETWORKING_RESOURCE_GROUP $USER_VNET_NAME "28" "1"
		SEARCH_OUTBOUND_SUBNET=$(echo "$SUBNETS_CIDR" | sed 's/[][]//g')
		echo "SEARCH_OUTBOUND_SUBNET: $SEARCH_OUTBOUND_SUBNET"
	else
		check_network_availability
	fi
	### "NAC Scheduler is not present. Creating new Virtual machine."
	echo "INFO ::: NAC Scheduler Instance is not present. Creating new Virtual Machine."
	########## Download NAC Scheduler Instance Provisioning Code from GitHub ##########
	### GITHUB_ORGANIZATION defaults to nasuni-labs
	REPO_FOLDER="nasuni-azure-analyticsconnector-manager"
	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
	GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo "INFO ::: Begin - Git Clone to ${GIT_REPO}"
	echo "INFO ::: $GIT_REPO"
	echo "INFO ::: GIT_REPO_NAME - $GIT_REPO_NAME"
	pwd
	rm -rf "${GIT_REPO_NAME}"
	COMMAND="git clone -b ${GIT_BRANCH_NAME} ${GIT_REPO}"
	$COMMAND
	RESULT=$?
	if [ $RESULT -eq 0 ]; then
		echo "INFO ::: git clone SUCCESS for repo ::: $GIT_REPO_NAME"
		cd "${GIT_REPO_NAME}"
	elif [ $RESULT -eq 128 ]; then
		cd "${GIT_REPO_NAME}"
		echo "$GIT_REPO_NAME"
		COMMAND="git pull origin main"
		$COMMAND
	fi
	### Download Provisioning Code from GitHub completed
	echo "INFO ::: NAC Scheduler VM provisioning ::: BEGIN - Executing ::: Terraform init . . . . . . . . "
	COMMAND="terraform init"
	$COMMAND
	echo "INFO ::: NAC Scheduler VM provisioning ::: FINISH - Executing ::: Terraform init."
	echo "INFO ::: NAC Scheduler VM provisioning ::: BEGIN - Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
	### Create .tfvars file to be used by the NACScheduler Instance Provisioning
	pwd
	TFVARS_NAC_SCHEDULER="NACScheduler.tfvars"
	rm -rf "$TFVARS_NAC_SCHEDULER" 
	chmod 755 $PEM_KEY_PATH
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	echo "sp_application_id="\"$SP_APPLICATION_ID\" >>$TFVARS_NAC_SCHEDULER
	echo "sp_secret="\"$SP_SECRET\" >>$TFVARS_NAC_SCHEDULER
	echo "subscription_id="\"$AZURE_SUBSCRIPTION_ID\" >>$TFVARS_NAC_SCHEDULER
	echo "edgeappliance_resource_group="\"$EDGEAPPLIANCE_RESOURCE_GROUP\" >>$TFVARS_NAC_SCHEDULER
	echo "networking_resource_group="\"$NETWORKING_RESOURCE_GROUP\" >>$TFVARS_NAC_SCHEDULER
	echo "region="\"$AZURE_LOCATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$NAC_SCHEDULER_NAME" != "" ]]; then
		echo "nac_scheduler_name="\"$NAC_SCHEDULER_NAME\" >>$TFVARS_NAC_SCHEDULER
		### Create entries about the Pem Key in the TFVARS File
	fi
	echo "pem_key_path="\"$PEM\" >>$TFVARS_NAC_SCHEDULER
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$USER_VNET_NAME" != "" ]]; then
		echo "user_vnet_name="\"$USER_VNET_NAME\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$SUBNET_NAME" != "" ]]; then
		echo "user_subnet_name="\"$SUBNET_NAME\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$USE_PRIVATE_IP" != "" ]]; then
		echo "use_private_ip="\"$USE_PRIVATE_IP\" >>$TFVARS_NAC_SCHEDULER
	fi
	echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$TFVARS_NAC_SCHEDULER
    echo "acs_admin_app_config_name="\"$ACS_ADMIN_APP_CONFIG_NAME\" >>$TFVARS_NAC_SCHEDULER
    echo "git_branch="\"$GIT_BRANCH_NAME\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
		echo "search_outbound_subnet="$SEARCH_OUTBOUND_SUBNET >>$TFVARS_NAC_SCHEDULER
	fi
	echo "INFO ::: $TFVARS_NAC_SCHEDULER created"
	dos2unix $TFVARS_NAC_SCHEDULER

	COMMAND="terraform apply -var-file=$TFVARS_NAC_SCHEDULER -auto-approve"
	$COMMAND
	if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler VM provisioning ::: FINISH - Executing ::: Terraform apply ::: SUCCESS."
	else
		echo "ERROR ::: NAC Scheduler VM provisioning ::: FINISH - Executing ::: Terraform apply ::: FAILED."
		exit 1
	fi
	ip=$(cat NACScheduler_IP.txt)
	NAC_SCHEDULER_IP_ADDR=$ip
	echo 'INFO ::: New pubilc IP just created:-'$ip
	pwd
	cd ../
	pwd
	echo "Pem key path: $PEM_KEY_PATH"
	sudo chmod 400 $PEM_KEY_PATH
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR
fi

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs / 3600)) $((secs % 3600 / 60)) $((secs % 60)))
echo "INFO ::: Total execution Time ::: $DIFF"
)2>&1 | tee $LOG_FILE
