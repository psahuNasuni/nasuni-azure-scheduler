#!/bin/bash

##############################################
## Pre-Requisite(S):						##
## 		- Git, AZURE CLI, JQ 				##
##		- AZURE Subscription				##
##############################################
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
START=$(date +%s)

check_if_subnet_exists() {

	INPUT_SUBNET="$1"
	INPUT_VPC="$2"
	SUBNET_CHECK=`aws ec2 describe-subnets --filters "Name=subnet-id,Values=$INPUT_SUBNET" --region ${AZURE_REGION} --profile "${AZURE_SUBSCRIPTION}"`
	SUBNET=`echo $SUBNET_CHECK | jq -r '.Subnets[].SubnetId'`
	echo "$SUBNET ***"
	SUBNET_VPC=`echo $SUBNET_CHECK | jq -r '.Subnets[].VpcId'`
	# SUBNET_VPC=`aws ec2 describe-subnets --filters "Name=subnet-id,Values=$INPUT_SUBNET" --region ${AZURE_REGION} --profile "${AZURE_SUBSCRIPTION}" | jq -r '.Subnets[].VpcId'`
	echo "$SUBNET_VPC ****"
	VPC_IS="$SUBNET_VPC"
	SUBNET_IS="$SUBNET"
	AZ_IS=`echo $SUBNET_CHECK | jq -r '.Subnets[].AvailabilityZone'`
	echo "SUBNET_IS=$SUBNET_IS , VPC_IS=$VPC_IS, AZ_IS=$AZ_IS"
	if [ "$INPUT_VPC" == "" ] ; then
		INPUT_VPC=$VPC_IS
	fi
	if [ "$VPC_IS" != "$INPUT_VPC" ] ; then
		echo "ERROR ::: $INPUT_SUBNET is not a valid Subnet in VPC $INPUT_VPC."
		exit 1
	fi

	if [ "$SUBNET" == "null" ] || [ "$SUBNET" == "" ]; then
		echo "ERROR ::: Subnet $INPUT_SUBNET not available. Please provide a valid Subnet ID."
		exit 1
	else
		echo "INFO ::: Subnet $SUBNET_IS exists in VPC $VPC_IS" 
	fi
}

check_if_vpc_exists() {
INPUT_VPC="$1"

VPC_CHECK=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$INPUT_VPC" --region ${AZURE_REGION} --profile "${AZURE_SUBSCRIPTION}" | jq -r '.Vpcs[].VpcId'`
echo "$?"
VPC_0_SUBNET=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$INPUT_VPC" --region ${AZURE_REGION} --profile "${AZURE_SUBSCRIPTION}" | jq -r '.Subnets[0].SubnetId')
VPC_IS="$VPC_CHECK"
SUBNET_IS="$VPC_0_SUBNET"
AZ_IS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$INPUT_VPC" --region ${AZURE_REGION} --profile "${AZURE_SUBSCRIPTION}" | jq -r '.Subnets[0].AvailabilityZone')
echo "SUBNET_IS=$VPC_0_SUBNET , VPC_IS=$VPC_CHECK, AZ_IS=$AZ_IS"
if [ "$VPC_CHECK" == "null" ] || [ "$VPC_CHECK" == "" ]; then
	echo "ERROR ::: VPC $INPUT_VPC not available. Please provide a valid VPC ID."
	exit 1
else
	echo "INFO ::: VPC $VPC_IS is Valid" 
fi
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
	### parse_textfile_for_user_secret_keys_values user_sec.txt
	# echo "INFO ::: Inside nmc_endpoint_accessibility"
	echo "INFO ::: NAC_SCHEDULER_NAME ::: ${NAC_SCHEDULER_NAME}"
	echo "INFO ::: NAC_SCHEDULER_IP_ADDR ::: ${NAC_SCHEDULER_IP_ADDR}"
	# echo "INFO ::: PEM ::: ${PEM}"
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
parse_4thArgument_for_nac_KVPs() {
	KEYVAULT_NAME="$1"
	## Read the Secret from KeyVault, Get secrets Or get-secret-value
	SECRET_STRING=$(aws secretsmanager get-secret-value --secret-id "$KEYVAULT_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}")

	NAC_SCHEDULER_NAME=$(echo $SECRET_STRING | jq -r '.SecretString' | jq -r '.nac_scheduler_name')
	NMC_API_USERNAME=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_username')
	NMC_API_PASSWORD=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_password')
	NMC_API_ENDPOINT=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_endpoint')
	PEM_KEY_PATH=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.pem_key_path')
	GITHUB_ORGANIZATION=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.github_organization')
	USER_VPC_ID=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.user_vpc_id')
	USER_SUBNET_ID=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.user_subnet_id')
	USE_PRIVATE_IP=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.use_private_ip')
	
	echo "INFO ::: github_organization=$GITHUB_ORGANIZATION :: nac_scheduler_name=$NAC_SCHEDULER_NAME :: nmc_api_username=$NMC_API_USERNAME :: nmc_api_password=$NMC_API_PASSWORD :: nmc_api_endpoint=$NMC_API_ENDPOINT :: pem_key_path=$PEM_KEY_PATH"
	
	if [ "$GITHUB_ORGANIZATION" == "" ] || [ "$GITHUB_ORGANIZATION" == "null" ]; then
		GITHUB_ORGANIZATION="nasuni-labs"
		echo "INFO ::: Value of github_organization is set to default as $GITHUB_ORGANIZATION"	
	else 
		echo "INFO ::: Value of github_organization is $GITHUB_ORGANIZATION"	
	fi
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

check_if_secret_exists() {
	AZURE_KEYVAULT_NAME="$1"
	AZURE_SUBSCRIPTION="$2"
	AZURE_REGION="$3"
	# Verify the Secret Exists in KeyVault
	if [[ -n $AZURE_KEYVAULT_NAME ]]; then
		COMMAND=`aws secretsmanager get-secret-value --secret-id ${AZURE_KEYVAULT_NAME} --profile ${AZURE_SUBSCRIPTION} --region ${AZURE_REGION}`
		RES=$?
		if [[ $RES -eq 0 ]]; then
			### echo "INFO ::: Secret ${AZURE_KEYVAULT_NAME} Exists. $RES"
			echo "Y"
		else
			### echo "ERROR ::: $RES :: Secret ${AZURE_KEYVAULT_NAME} Does'nt Exist in ${AZURE_REGION} region. OR, Invalid Secret name passed as 4th parameter"
			echo "N"
			# exit 0
		fi
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
	SECRET_NAME=$1
	SECRET_KEY=$2
	AZURE_REGION=$3
	AZURE_SUBSCRIPTION=$4
	echo "INFO ::: Validating Secret_key ::: $SECRET_KEY in secret-id $SECRET_NAME (in region $AZURE_REGION)"
	SECRET_VALUE=""
	if [ "$SECRET_KEY" == "nmc_api_username" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.nmc_api_username')
	elif [ "$SECRET_KEY" == "nmc_api_password" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.nmc_api_password')
	elif [ "$SECRET_KEY" == "nac_product_key" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.nac_product_key')
	elif [ "$SECRET_KEY" == "nmc_api_endpoint" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.nmc_api_endpoint')
	elif [ "$SECRET_KEY" == "web_access_appliance_address" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.web_access_appliance_address')
	elif [ "$SECRET_KEY" == "destination_bucket" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.destination_bucket')
	elif [ "$SECRET_KEY" == "volume_key" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.volume_key')
	elif [ "$SECRET_KEY" == "pem_key_path" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AZURE_REGION}" --profile "${AZURE_SUBSCRIPTION}" | jq -r '.SecretString' | jq -r '.pem_key_path')
	fi
	if [ -z "$SECRET_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key $SECRET_KEY = $SECRET_VALUE in secret $SECRET_NAME."
        exit 1
	else
		if [ "$SECRET_VALUE" == "null" ] ; then
			echo "ERROR ::: Validation FAILED as, Key $SECRET_KEY does not exists in secret $SECRET_NAME." 
			exit 1
		else 
			echo "INFO ::: Validation SUCCESS, as key $SECRET_KEY has value $SECRET_VALUE in secret $SECRET_NAME."
		fi
	fi
}

###########Adding Local IP to Security Group which is realted to NAC Public IP Address
add_ip_to_sec_grp() {
	NAC_SCHEDULER_IP_ADDR=$1
	echo "INFO ::: Getting Public IP of the local machine."
	echo $(curl checkip.amazonaws.com) >LOCAL_IP.txt

	LOCAL_IP=$(cat LOCAL_IP.txt)
	rm -rf LOCAL_IP.txt
	echo "INFO ::: Public IP of the local machine is ${LOCAL_IP}"
	NEW_CIDR="${LOCAL_IP}"/32
	echo "INFO ::: NEW_CIDR :- ${NEW_CIDR}"
	### Get Security group of NAC Scheduler
	SECURITY_GROUP_ID=$(aws ec2 describe-instances --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,SecurityGroups:SecurityGroups[*]}" --filters "Name=tag:Name,Values='$NAC_SCHEDULER_NAME'" "Name=instance-state-name,Values=running" --region $AZURE_REGION --profile $AZURE_SUBSCRIPTION | grep -e "GroupId" | cut -d":" -f 2 | tr -d '"')
	echo $SECURITY_GROUP_ID
	echo "INFO ::: Security group of $NAC_SCHEDULER_NAME is $SECURITY_GROUP_ID"
	status=$(aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --profile "${AZURE_SUBSCRIPTION}" --protocol tcp --port 22 --cidr ${NEW_CIDR} 2>/dev/null)
	if [ $? -eq 0 ]; then
		echo "INFO ::: Local Computer IP $NEW_CIDR updated to inbound rule of Security Group $SECURITY_GROUP_ID"
	else
		echo "INFO ::: IP $NEW_CIDR already available in inbound rule of Security Group $SECURITY_GROUP_ID"
	fi

}

######################## Validating AZURE Subscription for NAC ####################################
AZURE_SUBSCRIPTION="<<SUBSCRIPTION ID>>"
AZURE_REGION=""
AZURE_TENANT_ID=""
AZURE_USER_KEYVAULT=""
ARG_COUNT="$#"

validate_AZURE_SUBSCRIPTION() {
	echo "INFO ::: Validating AZURE Subscription ${AZURE_SUBSCRIPTION} for NAC  . . . . . . . . . . . . . . . . !!!"

	## TO UPDATE AS IN AZURE current_config
	if [[ "$(grep '^[[]profile' <~/.aws/config | awk '{print $2}' | sed 's/]$//' | grep "${AZURE_SUBSCRIPTION}")" == "" ]]; then
		echo "ERROR ::: AZURE Subscription ${AZURE_SUBSCRIPTION} does not exists. To Create AZURE Subscription, Run cli command - aws configure "
		exit 1
	else # AZURE Subscription nasuni available 
		AZURE_TENANT_ID=$(aws configure get AZURE_TENANT_ID --profile ${AZURE_SUBSCRIPTION})
		AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile ${AZURE_SUBSCRIPTION})
		AZURE_REGION=`aws configure get region --profile ${AZURE_SUBSCRIPTION}`
	fi

	echo "INFO ::: AZURE_REGION=$AZURE_REGION"
	echo "INFO ::: NMC_VOLUME_NAME=$NMC_VOLUME_NAME"
	echo "INFO ::: AZURE Subscription Validation SUCCESS !!!"
}
########################## Create CRON ############################################################
Schedule_CRON_JOB() {
	NAC_SCHEDULER_IP_ADDR=$1
	PEM="$PEM_KEY_PATH"
	check_if_pem_file_exists $PEM

	chmod 400 $PEM

	echo "INFO ::: Public IP Address:- $NAC_SCHEDULER_IP_ADDR"
	echo "ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"
	### Create TFVARS File for PROVISION_NAC.SH which is Used by CRON JOB - to Provision NAC Stack
	CRON_DIR_NAME="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	TFVARS_FILE_NAME="${CRON_DIR_NAME}.tfvars"
	rm -rf "$TFVARS_FILE_NAME"
	arn=$(aws sts get-caller-identity --profile nasuni| jq -r '.Arn' )
	AWS_CURRENT_USER=$(cut -d'/' -f2 <<<"$arn")
	echo "INFO ::: $AWS_CURRENT_USER which will be added for lambda layer::: "
	NEW_NAC_IP=$(echo $NAC_SCHEDULER_IP_ADDR | tr '.' '-')
	RND=$(( $RANDOM % 1000000 )); 
	LAMBDA_LAYER_SUFFIX=$(echo $RND)

	echo "INFO ::: $NEW_NAC_IP which will be added for lambda layer::: "
	echo "AZURE_SUBSCRIPTION="\"$AZURE_SUBSCRIPTION\" >>$TFVARS_FILE_NAME
	echo "region="\"$AZURE_REGION\" >>$TFVARS_FILE_NAME
	echo "volume_name="\"$NMC_VOLUME_NAME\" >>$TFVARS_FILE_NAME
	echo "user_secret="\"$USER_SECRET\" >>$TFVARS_FILE_NAME
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_FILE_NAME
	echo "nac_scheduler_ip_addr="\"$NEW_NAC_IP\" >>$TFVARS_FILE_NAME 
	echo "aws_current_user="\"$AWS_CURRENT_USER\" >>$TFVARS_FILE_NAME ### Append Current aws user
	echo "user_vpc_id="\"$USER_VPC_ID\" >>$TFVARS_FILE_NAME
	echo "user_subnet_id="\"$USER_SUBNET_ID\" >>$TFVARS_FILE_NAME
	echo "lambda_layer_suffix="\"$LAMBDA_LAYER_SUFFIX\" >>$TFVARS_FILE_NAME
	echo "frequency="\"$FREQUENCY\" >>$TFVARS_FILE_NAME
	echo "nac_scheduler_name="\"$NAC_SCHEDULER_NAME\" >>$TFVARS_FILE_NAME
	if [[ "$USE_PRIVATE_IP" == "Y" ]]; then
		echo "use_private_ip="\"$USE_PRIVATE_IP\" >>$TFVARS_FILE_NAME
	fi
	if [ $ARG_COUNT -eq 5 ]; then
		echo "INFO ::: $ARG_COUNT th Argument is supplied as ::: $NAC_INPUT_KVP"
		append_nac_keys_values_to_tfvars $NAC_INPUT_KVP $TFVARS_FILE_NAME
	fi
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null create_layer.sh tracker_json.py ubuntu@$NAC_SCHEDULER_IP_ADDR:~/ #SSA
	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to Copy create_layer.sh to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO :::create_layer.sh Uploaded Successfully to NAC_Scheduer Instance."
	fi
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "dos2unix create_layer.sh" #SSA
	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to do dos2unix create_layer.sh to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO :::create_layer.sh executed dos2unix Successfully to NAC_Scheduer Instance."
	fi
	#pass pub_ip to fun SSA
	#IAM_USER to be defined. et user 
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "sh create_layer.sh nasuni-labs-os-lambda-layer $AZURE_SUBSCRIPTION $NAC_SCHEDULER_IP_ADDR $AWS_CURRENT_USER $LAMBDA_LAYER_SUFFIX" #SSA
	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to execute create_layer.sh to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO :::create_layer.sh executed Successfully to NAC_Scheduer Instance."
	fi
	# echo "Exiting from "
	# exit 1
	### Create Directory for each Volume
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "[ ! -d $CRON_DIR_NAME ] && mkdir $CRON_DIR_NAME "
	### Copy TFVARS and provision_nac.sh to NACScheduler
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null provision_nac.sh "$TFVARS_FILE_NAME" ubuntu@$NAC_SCHEDULER_IP_ADDR:~/$CRON_DIR_NAME

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
	CRON_VOL=$(ssh -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ubuntu@"$NAC_SCHEDULER_IP_ADDR" "crontab -l |grep /home/ubuntu/$CRON_DIR_NAME/$TFVARS_FILE_NAME")
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
	ANALYTICS_SERVICE="ES" # ElasticSearch Service as default
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
validate_AZURE_SUBSCRIPTION
########## Check If fourth argument is provided
USER_SECRET_EXISTS="N"
if [[ -n "$FOURTH_ARG" ]]; then
	####  Fourth Argument is passed by User as a KeyVault Name
	echo "INFO ::: Fourth Argument $FOURTH_ARG is passed as User Secret Name"
	AZURE_KEYVAULT_NAME="$FOURTH_ARG"
	
	### Verify the KeyVault Exists
	AZURE_KEYVAULT_EXISTS=$(check_if_secret_exists $AZURE_KEYVAULT_NAME ${AZURE_SUBSCRIPTION} ${AZURE_REGION})
	echo "INFO ::: User secret Exists:: $AZURE_KEYVAULT_EXISTS"
	# if [ "${#AZURE_KEYVAULT_EXISTS}" -gt 0 ]; then
	if [ "$AZURE_KEYVAULT_EXISTS" == "Y" ]; then
		### Validate Keys in the Secret
		echo "INFO ::: Check if all Keys are provided"
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc_api_username "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc_api_password "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" nac_product_key "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" nmc_api_endpoint "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" web_access_appliance_address "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" destination_bucket "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" volume_key "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		validate_secret_values "$AZURE_KEYVAULT_NAME" pem_key_path "$AZURE_REGION" "$AZURE_SUBSCRIPTION"
		echo "INFO ::: Validation SUCCESS for all mandatory Secret-Keys !!!" 
	fi
else
	echo "INFO ::: Fourth argument is NOT provided, So, It will consider prod/nac/admin as the default user secret."
fi

echo "INFO ::: Get IP Address of NAC Scheduler Instance"
######################  NAC Scheduler Instance is Available ##############################

NAC_SCHEDULER_NAME=""
### parse_4thArgument_for_nac_KVPs "$FOURTH_ARG"
parse_4thArgument_for_nac_KVPs "$FOURTH_ARG"
echo "INFO ::: nac_scheduler_name = $NAC_SCHEDULER_NAME "
if [ "$NAC_SCHEDULER_NAME" != "" ]; then
	### User has provided the NACScheduler Name as Key-Value from 4th Argument
	if [[ "$USE_PRIVATE_IP" != "Y" ]]; then
		### Getting Public_IP of NAC Scheduler
		NAC_SCHEDULER_IP_ADDR=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress}" --filters "Name=tag:Name,Values='$NAC_SCHEDULER_NAME'" "Name=instance-state-name,Values=running" --region "${AZURE_REGION}" --profile ${AZURE_SUBSCRIPTION}| grep -e "PublicIP" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
		echo "INFO ::: Public_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
	else
		### Getting Private_IP of NAC Scheduler
		echo "INFO ::: Private_IP of NAC Scheduler is: $NAC_SCHEDULER_IP_ADDR"
		NAC_SCHEDULER_IP_ADDR=`aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PrivateIp:PrivateIpAddress}" --filters "Name=tag:Name,Values='$NAC_SCHEDULER_NAME'" "Name=instance-state-name,Values=running" --region "${AZURE_REGION}" --profile ${AZURE_SUBSCRIPTION} | grep -e "PrivateIp" | cut -d":" -f 2 | tr -d '"' | tr -d ' '`
	fi
else
	NAC_SCHEDULER_IP_ADDR=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress}" --filters "Name=tag:Name,Values='NACScheduler'" "Name=instance-state-name,Values=running" --region "${AZURE_REGION}" --profile ${AZURE_SUBSCRIPTION}| grep -e "PublicIP" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
fi
echo "INFO ::: NAC_SCHEDULER_IP_ADDR ::: $NAC_SCHEDULER_IP_ADDR"
if [ "$NAC_SCHEDULER_IP_ADDR" != "" ]; then
	echo "INFO ::: NAC Scheduler Instance is Available. IP Address: $NAC_SCHEDULER_IP_ADDR"
	### Call this function to add Local public IP to Security group of NAC_SCHEDULER IP
	add_ip_to_sec_grp $NAC_SCHEDULER_IP_ADDR $NAC_SCHEDULER_NAME
	### nmc endpoint accessibility $NAC_SCHEDULER_NAME $NAC_SCHEDULER_IP_ADDR
	# nmc_endpoint_accessibility  $NAC_SCHEDULER_NAME $NAC_SCHEDULER_IP_ADDR $NMC_API_ENDPOINT $NMC_API_USERNAME $NMC_API_PASSWORD #458
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR

###################### NAC Scheduler EC2 Instance is NOT Available ##############################
else
	## "NAC Scheduler is not present. Creating new EC2 machine."
	if [ "$USER_VPC_ID" == "" ] || [ "$USER_VPC_ID" == "null" ]; then
		echo "INFO ::: user_vpc_id not provided in the user Secret"  
		if [ "$USER_SUBNET_ID" == "" ] || [ "$USER_SUBNET_ID" == "null" ]; then
		### Both user_vpc_id and user_subnet_id not provided , It will take Default VPC and Subnet
			echo "INFO ::: user_subnet_id not provided in the user Secret, Provisioning will be done in the Default VPC Subnet"
		
		else
		### user_vpc_id not provided but, user_subnet_id provided 
			echo "INFO ::: user_subnet_id provided in the user Secret as user_subnet_id=$USER_SUBNET_ID"  
			check_if_subnet_exists $USER_SUBNET_ID $USER_VPC_ID

		fi
	else
		### If user_vpc_id provided
		if [ "$USER_SUBNET_ID" == "" ] || [ "$USER_SUBNET_ID" == "null" ]; then
		### If user_vpc_id provided and user_subnet_id not Provided, It will take the provided VPC ID and its default Subnet
			echo "INFO ::: user_subnet_id not provided in the user Secret, Provisioning will be done in the Provided VPC $USER_VPC_ID and its default Subnet"
			check_if_vpc_exists $USER_VPC_ID

		else
		### If user_vpc_id provided and user_subnet_id Provided, It will take the provided VPC ID and provided Subnet
			echo "INFO ::: user_vpc_id and user_subnet_id Provided in the user Secret, Provisioning will be done in the Provided VPC $USER_VPC_ID and Subnet $USER_SUBNET_ID"
			# check_if_subnet_exists $USER_SUBNET_ID
			check_if_subnet_exists $USER_SUBNET_ID $USER_VPC_ID

		fi
	fi
	echo "INFO ::: NAC Scheduler Instance is not present. Creating new EC2 machine."
	########## Download NAC Scheduler Instance Provisioning Code from GitHub ##########
	### GITHUB_ORGANIZATION defaults to nasuni-labs
	REPO_FOLDER="nasuni-azure-analyticsconnector-manager"
	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
	GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo "INFO ::: Begin - Git Clone to ${GIT_REPO}"
	echo "INFO ::: $GIT_REPO"
	echo "INFO ::: GIT_REPO_NAME - $GIT_REPO_NAME"
	pwd
	# ls
	rm -rf "${GIT_REPO_NAME}"
	COMMAND="git clone -b main ${GIT_REPO}"
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
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: BEGIN - Executing ::: Terraform init . . . . . . . . "
	COMMAND="terraform init"
	$COMMAND
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform init."
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: BEGIN - Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
	### Create .tfvars file to be used by the NACScheduler Instance Provisioning
	pwd
	TFVARS_NAC_SCHEDULER="NACScheduler.tfvars"
	rm -rf "$TFVARS_NAC_SCHEDULER" 
    AZURE_KEY=$(echo ${PEM_KEY_PATH} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	PEM="$AZURE_KEY.pem"
	### Copy the Pem Key from provided path to current folder
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	# TB Change As needed - START
	echo "AZURE_SUBSCRIPTION="\"$AZURE_SUBSCRIPTION\" >>$TFVARS_NAC_SCHEDULER
	echo "region="\"$AZURE_REGION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$NAC_SCHEDULER_NAME" != "" ]]; then
		echo "nac_scheduler_name="\"$NAC_SCHEDULER_NAME\" >>$TFVARS_NAC_SCHEDULER
		### Create entries about the Pem Key in the TFVARS File
		echo "pem_key_file="\"$PEM\" >>$TFVARS_NAC_SCHEDULER
	fi
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$VPC_IS" != "" ]]; then
		echo "user_vpc_id="\"$VPC_IS\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$SUBNET_IS" != "" ]]; then
		echo "user_subnet_id="\"$SUBNET_IS\" >>$TFVARS_NAC_SCHEDULER
	fi
	if [[ "$USE_PRIVATE_IP" != "" ]]; then
		echo "use_private_ip="\"$USE_PRIVATE_IP\" >>$TFVARS_NAC_SCHEDULER
	fi
	# TB Change As needed - END

	echo "$TFVARS_NAC_SCHEDULER created"
	echo `cat $TFVARS_NAC_SCHEDULER`

	dos2unix $TFVARS_NAC_SCHEDULER
	COMMAND="terraform apply -var-file=$TFVARS_NAC_SCHEDULER -auto-approve"
	$COMMAND
	if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: SUCCESS."
	else
		echo "ERROR ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: FAILED."
		exit 1
	fi
	ip=$(cat NACScheduler_IP.txt)
	NAC_SCHEDULER_IP_ADDR=$ip
	echo 'INFO ::: New pubilc IP just created:-'$ip
	pwd
	cd ../
	pwd
	## Call this function to add Local public IP to Security group of NAC_SCHEDULER IP
	add_ip_to_sec_grp ${NAC_SCHEDULER_IP_ADDR}
	## nmc endpoint accessibility $NAC_SCHEDULER_NAME $NAC_SCHEDULER_IP_ADDR
	#nmc_endpoint_accessibility  $NAC_SCHEDULER_NAME ${NAC_SCHEDULER_IP_ADDR} $NMC_API_ENDPOINT $NMC_API_USERNAME $NMC_API_PASSWORD #458
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR

fi

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs / 3600)) $((secs % 3600 / 60)) $((secs % 60)))
echo "INFO ::: Total execution Time ::: $DIFF"
#exit 0
