#!/bin/bash

##############################################
## Pre-Requisite(S):						##
## 		- Git, AZURE CLI, JQ 				##
##		- AZURE Subscription				##
##############################################
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
START=$(date +%s)

check_if_subnet_exists(){
	INPUT_SUBNET="$1"
	INPUT_VNET="$2"
  	INPUT_RG="$3"

    VNET_CHECK=`az network vnet show --name $INPUT_VNET --resource-group $INPUT_RG | jq -r .provisioningState`
    if [ "$VNET_CHECK" != "Succeeded" ]; then
     	echo "ERROR ::: VNET $INPUT_VNET not available. Please provide a valid VNET NAME."
    	exit 1
    else
     	echo "INFO ::: VNET $INPUT_VNET is Valid" 
        # if vnet is valid then checking for subnet is valid or not
        SUBNET_CHECK=`az network vnet subnet show --name $INPUT_SUBNET --vnet-name $INPUT_VNET --resource-group $INPUT_RG | jq -r .provisioningState`
        if [ "$SUBNET_CHECK" != "Succeeded" ]; then
            echo "ERROR ::: SUBNET $INPUT_SUBNET not available. Please provide a valid SUBNET NAME."
            exit 1
        else
            echo "INFO ::: SUBNET $INPUT_SUBNET is Valid"
        fi
     fi
  	VNET_IS="$INPUT_VNET"
	SUBNET_IS="$INPUT_SUBNET"
	echo "SUBNET_IS=$SUBNET_IS , VNET_IS=$VNET_IS"
}

check_if_VNET_exists(){
INPUT_VNET="$1"
INPUT_RG="$2"

VNET_CHECK=`az network vnet show --name $INPUT_VNET --resource-group $INPUT_RG | jq -r .provisioningState`
if [ "$VNET_CHECK" == "Succeeded" ]; then
	echo "INFO ::: VNET $INPUT_VNET is Valid" 
else
	echo "ERROR ::: VNET $INPUT_VNET not available. Please provide a valid VNET NAME."
	exit 1
fi

VNET_0_SUBNET=`az network vnet show --name $INPUT_VNET --resource-group $INPUT_RG | jq -r .subnets[0].name`
VNET_IS="$INPUT_VNET"
SUBNET_IS="$VNET_0_SUBNET"
echo "SUBNET_IS=$VNET_0_SUBNET , VNET_IS=$INPUT_VNET"

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

nmc_endpoint_accessibility() {
	NAC_SCHEDULER_NAME="$1"
	NAC_SCHEDULER_IP_ADDR="$2"
    NMC_API_ENDPOINT="$3"
	NMC_API_USERNAME="$4"
	NMC_API_PASSWORD="$5" #14-19
	PEM="$PEM_KEY_PATH"

	chmod 400 $PEM
	### nac_scheduler_name = from FourthArgument of NAC_Scheduler.sh, user_sec.txt
	echo "INFO ::: NAC_SCHEDULER_NAME ::: ${NAC_SCHEDULER_NAME}"
	echo "INFO ::: NAC_SCHEDULER_IP_ADDR ::: ${NAC_SCHEDULER_IP_ADDR}"
	echo "INFO ::: NMC_API_ENDPOINT ::: ${NMC_API_ENDPOINT}"
	echo "INFO ::: NMC_API_USERNAME ::: ${NMC_API_USERNAME}"
	echo "INFO ::: NMC_API_PASSWORD ::: ${NMC_API_PASSWORD}" # 31-37

	echo "INFO ::: NAC_SCHEDULER_IP_ADDR : "$NAC_SCHEDULER_IP_ADDR
	py_file_name=$(ls check_nmc_visiblity.py)
	echo "INFO ::: Executing Python code file : "$py_file_name
	cat $py_file_name | ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null python3 - $NMC_API_USERNAME $NMC_API_PASSWORD $NMC_API_ENDPOINT
	if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler with IP : ${NAC_SCHEDULER_IP_ADDR}, have access to NMC API ${NMC_API_ENDPOINT} "
	else
		echo "ERROR ::: NAC Scheduler with IP : ${NAC_SCHEDULER_IP_ADDR}, Does NOT have access to NMC API ${NMC_API_ENDPOINT}. Please configure access to NMC "
		exit 1
	fi
	echo "INFO ::: Completed NMC endpoint accessibility Check. !!!"

}

append_nac_keys_values_to_tfvars() {
	inputFile="$1" ### Read InputFile
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
	if [[ "$(az keyvault list -o tsv | cut -f 3 | grep -w ${AZURE_KEYVAULT_NAME})" == "" ]]; then
		echo "N"
	else
		echo "Y"
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

validate_secret_values() {
	KEY_VAULT_NAME=$1
	SECRET_NAME=$2
	echo "INFO ::: Validating Secret ::: $SECRET_NAME in Key Vault $KEY_VAULT_NAME"
	SECRET_VALUE=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$SECRET_NAME" --query value --output tsv)

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
			elif [ "$SECRET_NAME" == "vnet" ]; then
				VNET_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "use-private-ip" ]; then
				USE_PRIVATE_IP=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "pem-key-path" ]; then
				PEM_KEY_PATH=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "acs-key-vault-name" ]; then
				ACS_KEY_VAULT_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "acs-resource-group" ]; then
				ACS_RESOURCE_GROUP=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "acs-service-name" ]; then
				ACS_SERVICE_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "github-organization" ]; then
				GITHUB_ORGANIZATION=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "destination-container-url" ]; then
				DESTINATION_CONTAINER_URL=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "volume-key-container-url" ]; then
				VOLUME_KEY_BLOB_URL=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nac-scheduler-resource-group" ]; then
				NAC_SCHEDULER_RESOURCE_GROUP=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "nac-scheduler-name" ]; then
				NAC_SCHEDULER_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "user-vnet-name" ]; then
				USER_VNET_NAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "azure-username" ]; then
				AZURE_USERNAME=$SECRET_VALUE
			elif [ "$SECRET_NAME" == "azure-password" ]; then
				AZURE_PASSWORD=$SECRET_VALUE
            fi
			echo "INFO ::: Validation SUCCESS, as key $SECRET_NAME has value $SECRET_VALUE in Key Vault $KEY_VAULT_NAME."
		fi
	fi
	if [ -z "$SECRET_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key $SECRET_NAME = $SECRET_VALUE in secret $SECRET_NAME."
        exit 1
	fi
}

######################## Validating AZURE Subscription for NAC ####################################
ARG_COUNT="$#"

validate_AZURE_SUBSCRIPTION() {
	echo "INFO ::: Validating AZURE Subscription ${AZURE_SUBSCRIPTION} for NAC  . . . . . . . . . . . . . . . . !!!"
	AZURE_SUBSCRIPTION_STATUS=`az account list -o tsv | cut -f 6 | grep -w "${AZURE_SUBSCRIPTION}"`
	echo "$AZURE_SUBSCRIPTION_STATUS"
	if [ "$AZURE_SUBSCRIPTION_STATUS" == "" ]; then
		echo "ERROR ::: AZURE Subscrip ${AZURE_SUBSCRIPTION} does not exists. To Create AZURE Subscription, Run cli command - az login"
		exit 1
	else
		COMMAND=`az account set --subscription "${AZURE_SUBSCRIPTION}"`
		AZURE_TENANT_ID="$(az account list --query "[?isDefault].tenantId" -o tsv)"
		AZURE_SUBSCRIPTION_ID="$(az account list --query "[?isDefault].id" -o tsv)"
	fi

	echo "INFO ::: AZURE_TENANT_ID=$AZURE_TENANT_ID"
	echo "INFO ::: AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"
	echo "INFO ::: AZURE Subscription Validation SUCCESS !!!"
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
	LAMBDA_LAYER_SUFFIX=$(echo $RND)

	### NMC API CALL
	###'Usage -- python3 fetch_nmc_api_23-8.py <ip_address> <username> <password> <volume_name> <rid> <web_access_appliance_address>')
	python3 fetch_volume_data_from_nmc_api.py ${NMC_API_ENDPOINT} ${NMC_API_USERNAME} ${NMC_API_PASSWORD} ${NMC_VOLUME_NAME} ${RND} ${WEB_ACCESS_APPLIANCE_ADDRESS}
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

	### DESTINATION_BUCKET_URL="https://destinationbktsa.blob.core.windows.net/destinationbkt" ## "From_Key_Vault"
	DESTINATION_CONTAINER_NAME=$(echo ${DESTINATION_CONTAINER_URL} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)

	### https://destinationbktsa.blob.core.windows.net/destinationbkt From this we can get DESTINATION_STORAGE_ACCOUNT_NAME=destinationbktsa and DESTINATION_BUCKET_NAME=destinationbkt  and DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=az storage account show-connection-string --name nmcfilersa

	DESTINATION_STORAGE_ACCOUNT_NAME=$(echo ${DESTINATION_CONTAINER_URL} | cut -d/ -f3-|cut -d'.' -f1) #"destinationbktsa"

	### Destination account-key: 
	DESTINATION_ACCOUNT_KEY=`az storage account keys list --account-name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.[0].value'`
	DESTINATION_CONTAINER_TOCKEN=`az storage account generate-sas --expiry ${SAS_EXPIRY} --permissions wdl --resource-types co --services b --account-key ${DESTINATION_ACCOUNT_KEY} --account-name ${DESTINATION_STORAGE_ACCOUNT_NAME} --https-only`
	DESTINATION_CONTAINER_TOCKEN=$(echo "$DESTINATION_CONTAINER_TOCKEN" | tr -d \")
	DESTINATION_CONTAINER_SAS_URL="https://$DESTINATION_STORAGE_ACCOUNT_NAME.blob.core.windows.net/?$DESTINATION_CONTAINER_TOCKEN"
	### Destination Bucket COnnection String ==> datasource_connection_string, Used for CognitiveSearch Provisioning ###datasource_connection_string=DefaultEndpointsProtocol=https;AccountName=destinationbktsa;AccountKey=ekOsyrbVEGCbOQFIM6CaM3Ne7zdnct33ZuvSvp1feo1xtpQ/IMq15WD9TGXIeVvvuS0DO1mRMYYB+ASt1lMVKw==;EndpointSuffix=core.windows.net

	DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING=`az storage account show-connection-string --name ${DESTINATION_STORAGE_ACCOUNT_NAME} | jq -r '.connectionString'`

	### VOLUME_KEY_BUCKET_URL="https://keysa.blob.core.windows.net/key"  ##"From_Key_Vault"
	VOLUME_KEY_STORAGE_ACCOUNT_NAME=$(echo ${VOLUME_KEY_BLOB_URL}} | cut -d/ -f3-|cut -d'.' -f1) #"keysa"
	VOLUME_KEY_BLOB_NAME=$(echo $VOLUME_KEY_BLOB_URL | cut -d/ -f4)
	VOLUME_ACCOUNT_KEY=`az storage account keys list --account-name ${VOLUME_KEY_STORAGE_ACCOUNT_NAME} | jq -r '.[0].value'`
	VOLUME_KEY_BLOB_TOCKEN=`az storage blob generate-sas --account-name ${VOLUME_KEY_STORAGE_ACCOUNT_NAME} --name ${VOLUME_KEY_BLOB_NAME} --permissions r --expiry ${SAS_EXPIRY} --account-key ${VOLUME_ACCOUNT_KEY} --blob-url ${VOLUME_KEY_BLOB_URL} --https-only`
	VOLUME_KEY_BLOB_TOCKEN=$(echo "$VOLUME_KEY_BLOB_TOCKEN" | tr -d \")
	BLOB=$(echo $VOLUME_KEY_BLOB_URL | cut -d/ -f5)
	### https://keysa.blob.core.windows.net/key/sa-filer-01-20220726.pgp?sp
	VOLUME_KEY_BLOB_SAS_URL="https://$VOLUME_KEY_STORAGE_ACCOUNT_NAME.blob.core.windows.net/$VOLUME_KEY_BLOB_NAME/$BLOB?$VOLUME_KEY_BLOB_TOCKEN"

    ### Generating NAC Resource group name dynamically
    NAC_RESOURCE_GROUP_NAME="nac-resource-group-$RND"
    echo "Name: "$NAC_RESOURCE_GROUP_NAME >>$CONFIG_DAT_FILE_NAME
	### AzureSubscriptionID >>>>> Read from user_secret Key Vault
    echo "AzureSubscriptionID: "$AZURE_SUBSCRIPTION_ID >>$CONFIG_DAT_FILE_NAME
	### AzureLocation >>>>> Read from user_secret Key Vault
    echo "AzureLocation: "$AZURE_LOCATION>>$CONFIG_DAT_FILE_NAME
	### ProductKey >>>>> Read from user_secret Key Vault
    echo "ProductKey: "$PRODUCT_KEY>>$CONFIG_DAT_FILE_NAME
	### SourceContainer >>>>> Get from NMC_API Call
    echo "SourceContainer: "$SOURCE_CONTAINER >>$CONFIG_DAT_FILE_NAME
	### SourceContainerSASURL >>>>> Generate Dynamically by using az CLI commands
    echo "SourceContainerSASURL: "$SOURCE_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE_NAME
	### VolumeKeySASURL >>>>> Generate Dynamically by using az CLI commands
    echo "VolumeKeySASURL: "$VOLUME_KEY_BLOB_SAS_URL>>$CONFIG_DAT_FILE_NAME
	### VolumeKeyPassphrase >>>>> Recommended as 'null' for AZURE NAC
    echo "VolumeKeyPassphrase: "\'null\' >>$CONFIG_DAT_FILE_NAME
	### UniFSTOCHandle >>>>> Get from NMC_API Call
    echo "UniFSTOCHandle: "$UNIFS_TOC_HANDLE >>$CONFIG_DAT_FILE_NAME
	### PrevUniFSTOCHandle >>>>> will be taken from TrackerJSON. Currently taking as 'null' for AZURE NAC
    echo "PrevUniFSTOCHandle: "null >>$CONFIG_DAT_FILE_NAME
	### StartingPoint >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "StartingPoint: "/ >>$CONFIG_DAT_FILE_NAME
	### IncludeFilterPattern >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "IncludeFilterPattern: "\'*\' >>$CONFIG_DAT_FILE_NAME
	### IncludeFilterType >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "IncludeFilterType: "glob >>$CONFIG_DAT_FILE_NAME
	### ExcludeFilterPattern >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "ExcludeFilterPattern: "null >>$CONFIG_DAT_FILE_NAME
	### ExcludeFilterType >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "ExcludeFilterType: "glob >>$CONFIG_DAT_FILE_NAME
	### MinFileSizeFilter >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "MinFileSizeFilter: "0b >>$CONFIG_DAT_FILE_NAME
	### MaxFileSizeFilter >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "MaxFileSizeFilter: "5gb >>$CONFIG_DAT_FILE_NAME
    echo "DestinationContainer: "$DESTINATION_CONTAINER_NAME >>$CONFIG_DAT_FILE_NAME
    echo "DestinationContainerSASURL: "$DESTINATION_CONTAINER_SAS_URL >>$CONFIG_DAT_FILE_NAME
    echo "DestinationPrefix: "/ >>$CONFIG_DAT_FILE_NAME
	### ExcludeTempFiles >>>>> Static Variables, Can be overriden from 5th Argument to NAC_Scheduler.sh
    echo "ExcludeTempFiles: "\'True\' >>$CONFIG_DAT_FILE_NAME

    chmod 777 $CONFIG_DAT_FILE_NAME

	CRON_DIR_NAME="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	
	USER_PRINCIPAL_NAME=`az account show --query user.name | tr -d '"'`
	ACS_TFVARS_FILE="ACS.txt"
	rm -rf "$ACS_TFVARS_FILE"
	echo "acs_service_name="$ACS_SERVICE_NAME >>$ACS_TFVARS_FILE
	echo "acs_resource_group="$ACS_RESOURCE_GROUP >>$ACS_TFVARS_FILE
	echo "subscription_id="$AZURE_SUBSCRIPTION_ID >>$ACS_TFVARS_FILE
	echo "tenant_id="$AZURE_TENANT_ID >>$ACS_TFVARS_FILE
	echo "azure_location="$AZURE_LOCATION >>$ACS_TFVARS_FILE
	echo "acs-key-vault="$ACS_KEY_VAULT_NAME >>$ACS_TFVARS_FILE
	echo "datasource-connection-string="$DESTINATION_STORAGE_ACCOUNT_CONNECTION_STRING >>$ACS_TFVARS_FILE
	echo "destination-container-name="$DESTINATION_CONTAINER_NAME >>$ACS_TFVARS_FILE
	echo "nmc_volume_name="$NMC_VOLUME_NAME >>$ACS_TFVARS_FILE
	echo "github_organization="$GITHUB_ORGANIZATION >>$ACS_TFVARS_FILE
	echo "web_access_appliance_address="$WEB_ACCESS_APPLIANCE_ADDRESS >>$ACS_TFVARS_FILE
	echo "unifs_toc_handle="$UNIFS_TOC_HANDLE >>$ACS_TFVARS_FILE
	echo "user_principal_name="$USER_PRINCIPAL_NAME >>$ACS_TFVARS_FILE
	echo "" >>$ACS_TFVARS_FILE
   
    chmod 777 $ACS_TFVARS_FILE

	### Create Directory for each Volume
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "[ ! -d $CRON_DIR_NAME ] && mkdir $CRON_DIR_NAME "
	### Copy TFVARS and provision_nac.sh to NACScheduler
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null provision_nac.sh "$ACS_TFVARS_FILE" "$CONFIG_DAT_FILE_NAME" ubuntu@$NAC_SCHEDULER_IP_ADDR:~/$CRON_DIR_NAME

	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to Copy $TFVARS_FILE_NAME to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO ::: $TFVARS_FILE_NAME Uploaded Successfully to NAC_Scheduer Instance."
	fi
	rm -rf $TFVARS_FILE_NAME
	#dos2unix command execute
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "dos2unix ~/$CRON_DIR_NAME/provision_nac.sh"
	### Check If CRON JOB is running for a specific VOLUME_NAME
	CRON_VOL=$(ssh -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ubuntu@"$NAC_SCHEDULER_IP_ADDR" "crontab -l | grep /home/ubuntu/$CRON_DIR_NAME/$TFVARS_FILE_NAME")
	if [ "$CRON_VOL" != "" ]; then
		### DO Nothing. CRON JOB takes care of NAC Provisioning
		echo "INFO ::: crontab does not require volume entry.As it is already present.:::::"
	else
		### Set up a new CRON JOB for NAC Provisioning
		echo "INFO ::: Setting CRON JOB for $CRON_DIR_NAME as it is not present"
		ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "(crontab -l ; echo '*/$FREQUENCY * * * * cd ~/$CRON_DIR_NAME && /bin/bash provision_nac.sh  ~/$CRON_DIR_NAME/$TFVARS_FILE_NAME >> ~/$CRON_DIR_NAME/CRON_log-$CRON_DIR_NAME-$DATE_WITH_TIME.log 2>&1') | sort - | uniq - | crontab -"
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

### Validate AZURE_SUBSCRIPTION 
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
		validate_secret_values "$AZURE_KEYVAULT_NAME" acs-service-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" acs-resource-group
		validate_secret_values "$AZURE_KEYVAULT_NAME" web-access-appliance-address
		validate_secret_values "$AZURE_KEYVAULT_NAME" pem-key-path
		validate_secret_values "$AZURE_KEYVAULT_NAME" acs-key-vault-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" github-organization
		validate_secret_values "$AZURE_KEYVAULT_NAME" destination-container-url
		validate_secret_values "$AZURE_KEYVAULT_NAME" volume-key-container-url
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-endpoint
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-username
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc-api-password
		validate_secret_values "$AZURE_KEYVAULT_NAME" nac-scheduler-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" nac-scheduler-resource-group
		validate_secret_values "$AZURE_KEYVAULT_NAME" user-vnet-name
		validate_secret_values "$AZURE_KEYVAULT_NAME" azure-username
		validate_secret_values "$AZURE_KEYVAULT_NAME" azure-password


echo "INFO ::: Validation SUCCESS for all mandatory Secret-Keys !!!" 
	fi
else
	echo "INFO ::: Fourth argument is NOT provided, So, It will consider prod/nac/admin as the default key vault."
fi
validate_AZURE_SUBSCRIPTION

echo "INFO ::: Get IP Address of NAC Scheduler Instance"
######################  NAC Scheduler Instance is Available ##############################
USER_VNET_RESOURCE_GROUP=$NAC_SCHEDULER_RESOURCE_GROUP
### parse_4thArgument_for_nac_KVPs "$FOURTH_ARG"
echo "INFO ::: nac_scheduler_name = $NAC_SCHEDULER_NAME "
if [ "$NAC_SCHEDULER_NAME" != "" ]; then
	### User has provided the NACScheduler Name as Key-Value from 4th Argument
	if [[ "$USE_PRIVATE_IP" != "Y" ]]; then
		### Getting Public_IP of NAC Scheduler
		NAC_SCHEDULER_IP_ADDR=$(az vm list-ip-addresses --name $NAC_SCHEDULER_NAME --resource-group $NAC_SCHEDULER_RESOURCE_GROUP --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
		echo "INFO ::: Public_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
	else
		### Getting Private_IP of NAC Scheduler
		echo "INFO ::: Private_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
		NAC_SCHEDULER_IP_ADDR=`az vm list-ip-addresses --name $NAC_SCHEDULER_NAME --resource-group $NAC_SCHEDULER_RESOURCE_GROUP --query "[0].virtualMachine.network.privateIpAddresses[0]" | cut -d":" -f 2 | tr -d '"' | tr -d ' '`
	fi
else
	NAC_SCHEDULER_IP_ADDR=$(az vm list-ip-addresses --name NACScheduler --resource-group $NAC_SCHEDULER_RESOURCE_GROUP --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
fi
echo "INFO ::: NAC_SCHEDULER_IP_ADDR ::: $NAC_SCHEDULER_IP_ADDR"
if [ "$NAC_SCHEDULER_IP_ADDR" != "" ]; then
	echo "INFO ::: NAC Scheduler Instance is Available. IP Address: $NAC_SCHEDULER_IP_ADDR"
	echo $PEM_KEY_PATH
	AZURE_KEY=$(echo ${PEM_KEY_PATH} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo $AZURE_KEY
	PEM="$AZURE_KEY.pem"
	### Copy the Pem Key from provided path to current folder
	ls
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	### Call this function to add Local public IP to Network Security Group (NSG rule) of NAC_SCHEDULER IP
	ls
	echo $PEM
	### nmc endpoint accessibility $NAC_SCHEDULER_NAME $NAC_SCHEDULER_IP_ADDR
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR
	exit 111

###################### NAC Scheduler VM Instance is NOT Available ##############################
else
	## "NAC Scheduler is not present. Creating new Virtual machine."
    if [ "$USER_VNET_RESOURCE_GROUP" == "" ] || [ "$USER_VNET_RESOURCE_GROUP" == null ]; then
        echo "INFO ::: Azure Virtual Network Resource Group is Not provided."
        exit 1
    else
          ### If resource group already available
            echo "INFO ::: Azure Virtual Network Resource Group is provided as $USER_VNET_RESOURCE_GROUP"
    fi
	if [ "$USER_VNET_NAME" == "" ] || [ "$USER_VNET_NAME" == "null" ]; then
		echo "INFO ::: USER_VNET_NAME not provided in the user Secret"  
        exit 1
	else
		### If USER_VNET_NAME provided
		if [ "$USER_SUBNET_NAME" == "" ] || [ "$USER_SUBNET_NAME" == "null" ]; then
		### If USER_VNET_NAME provided and USER_SUBNET_NAME not Provided, It will take the provided VNET NAME and its default Subnet
			echo "INFO ::: USER_SUBNET_NAME not provided in the user Secret, Provisioning will be done in the Provided VNET $USER_VNET_NAME and its default Subnet"
			check_if_VNET_exists $USER_VNET_NAME $USER_VNET_RESOURCE_GROUP

		else
		### If USER_VNET_NAME provided and USER_SUBNET_NAME Provided, It will take the provided VNET NAME and provided Subnet
			echo "INFO ::: USER_VNET_NAME and USER_SUBNET_NAME Provided in the user Secret, Provisioning will be done in the Provided VNET $USER_VNET_NAME and Subnet $USER_SUBNET_NAME"
			check_if_subnet_exists $USER_SUBNET_NAME $USER_VNET_NAME $USER_VNET_RESOURCE_GROUP
		fi
	fi
	echo "INFO ::: NAC Scheduler Instance is not present. Creating new Virtual Machine."
	########## Download NAC Scheduler Instance Provisioning Code from GitHub ##########
	### GITHUB_ORGANIZATION defaults to nasuni-labs
	REPO_FOLDER="nasuni-azure-analyticsconnector-manager"
	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
	GIT_BRANCH_NAME="main"
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
	AZURE_KEY=$(echo ${PEM_KEY_PATH} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo $AZURE_KEY
	PEM="$AZURE_KEY.pem"
	chmod 755 $PEM_KEY_PATH
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	echo "azure_username="\"$AZURE_USERNAME\" >>$TFVARS_NAC_SCHEDULER
	echo "azure_password="\"$AZURE_PASSWORD\" >>$TFVARS_NAC_SCHEDULER
	echo "subscription_id="\"$AZURE_SUBSCRIPTION_ID\" >>$TFVARS_NAC_SCHEDULER
	echo "user_resource_group_name="\"$NAC_SCHEDULER_RESOURCE_GROUP\" >>$TFVARS_NAC_SCHEDULER
	echo "region="\"$AZURE_LOCATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$NAC_SCHEDULER_NAME" != "" ]]; then
		echo "nac_scheduler_name="\"$NAC_SCHEDULER_NAME\" >>$TFVARS_NAC_SCHEDULER
		### Create entries about the Pem Key in the TFVARS File
	fi
	echo "pem_key_path="\"$PEM\" >>$TFVARS_NAC_SCHEDULER
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$VNET_IS" != "" ]]; then
		echo "user_vnet_name="\"$VNET_IS\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$SUBNET_IS" != "" ]]; then
		echo "user_subnet_name="\"$SUBNET_IS\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$USE_PRIVATE_IP" != "" ]]; then
		echo "use_private_ip="\"$USE_PRIVATE_IP\" >>$TFVARS_NAC_SCHEDULER
	fi
	echo "acs_resource_group="\"$ACS_RESOURCE_GROUP\" >>$TFVARS_NAC_SCHEDULER
	echo "acs_key_vault="\"$ACS_KEY_VAULT_NAME\" >>$TFVARS_NAC_SCHEDULER
	echo "$TFVARS_NAC_SCHEDULER created"

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
	sudo chmod 400 $PEM
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR
fi

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs / 3600)) $((secs % 3600 / 60)) $((secs % 60)))
echo "INFO ::: Total execution Time ::: $DIFF"