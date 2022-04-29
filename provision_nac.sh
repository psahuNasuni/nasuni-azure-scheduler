#!/bin/bash

#############################################################################################
#### This Script Targets NAC Deployment from any Linux Box 
#### Prequisites: 
####       1- Software need to be Installed:
####             a- AZURE CLI 
####             b- Python 3
####             c- curl 
####             d- git 
####             e- jq 
####             f- wget 
####             e- Terraform V 1.0.7
####       2- Azure Active Directory should be configured 
####       3- NMC Volume 
####       5- User Specific AWS UserSecret  
####             a- User need to provide/Update valid values for below keys:
####
#############################################################################################
set -e

START=$(date +%s)
{
TFVARS_FILE=$1
read_TFVARS() {
  file="$TFVARS_FILE"
  while IFS="=" read -r key value; do
    case "$key" in
      "aws_profile") AWS_PROFILE="$value" ;;
      "region") AWS_REGION="$value" ;;
      "volume_name") NMC_VOLUME_NAME="$value" ;;
      "github_organization") GITHUB_ORGANIZATION="$value" ;;
    esac
  done < "$file"
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


parse_textfile_for_user_secret_keys_values() {
	file="$1"
	while IFS="=" read -r key value; do
		case "$key" in
		"nmc_api_username") NMC_API_USERNAME="$value" ;;
		"nmc_api_password") NMC_API_PASSWORD="$value" ;;
		"nac_product_key") NAC_PRODUCT_KEY="$value" ;;
		"nmc_api_endpoint") NMC_API_ENDPOINT="$value" ;;
		"web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
		"volume_key") VOLUME_KEY="$value" ;;
		"volume_key_passphrase") VOLUME_KEY_PASSPHRASE="$value" ;;
		"destination_bucket") DESTINATION_BUCKET="$value" ;;
		"pem_key_path") PEM_KEY_PATH="$value" ;;
        "acs_name") ACS_NAME="$value" ;;
        "acs_resource_group") ACS_RESOURCE_GROUP="$value" ;;
		esac
	done <"$file"
}

create_Config_Dat_file() {
### create Config Dat file, which is used for NAC Provisioning
    source $1
    CONFIG_DAT_FILE_NAME="/usr/local/bin/config.dat"
    rm -rf "$CONFIG_DAT_FILE_NAME" 
    echo "Name: "$Name >>$CONFIG_DAT_FILE_NAME
    echo "AzureSubscriptionID: "$AzureSubscriptionID >>$CONFIG_DAT_FILE_NAME
    echo "AzureLocation: "$AzureLocation >>$CONFIG_DAT_FILE_NAME
    echo "ProductKey: "$ProductKey >>$CONFIG_DAT_FILE_NAME
    echo "SourceContainer: "$SourceContainer >>$CONFIG_DAT_FILE_NAME
    echo "SourceContainerSASURL: "$SourceContainerSASURL >>$CONFIG_DAT_FILE_NAME
    echo "VolumeKeySASURL: "$VolumeKeySASURL >>$CONFIG_DAT_FILE_NAME
    echo "VolumeKeyPassphrase: "\'null\' >>$CONFIG_DAT_FILE_NAME
    echo "UniFSTOCHandle: "$UniFSTOCHandle >>$CONFIG_DAT_FILE_NAME
    echo "PrevUniFSTOCHandle: "null >>$CONFIG_DAT_FILE_NAME
    echo "StartingPoint: "/ >>$CONFIG_DAT_FILE_NAME
    echo "IncludeFilterPattern: "\'*\' >>$CONFIG_DAT_FILE_NAME
    echo "IncludeFilterType: "glob >>$CONFIG_DAT_FILE_NAME
    echo "ExcludeFilterPattern: "null >>$CONFIG_DAT_FILE_NAME
    echo "ExcludeFilterType: "glob >>$CONFIG_DAT_FILE_NAME
    echo "MinFileSizeFilter: "0b >>$CONFIG_DAT_FILE_NAME
    echo "MaxFileSizeFilter: "5gb >>$CONFIG_DAT_FILE_NAME
    echo "DestinationContainer: "$DestinationContainer >>$CONFIG_DAT_FILE_NAME
    echo "DestinationContainerSASURL: "$DestinationContainerSASURL >>$CONFIG_DAT_FILE_NAME
    echo "DestinationPrefix: "/ >>$CONFIG_DAT_FILE_NAME
    echo "ExcludeTempFiles: "\'True\' >>$CONFIG_DAT_FILE_NAME
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

USER_SECRET_TEXT_FILE="$1"

NMC_VOLUME_NAME=$(echo "$NMC_VOLUME_NAME" | tr -d '"')
# GITHUB_ORGANIZATION=$(echo "$GITHUB_ORGANIZATION" | tr -d '"')
GITHUB_ORGANIZATION="psahuNasuni"
ACS_NAME="acs name from user secret text"
ACS_RESOURCE_GROUP="acs resource_group from user secret text"
parse_textfile_for_user_secret_keys_values $USER_SECRET_TEXT_FILE

######################## Check If Azure Cognitice Search Available ###############################################

echo "INFO ::: ES_DOMAIN NAME : $ACS_NAME"
IS_ACS="N"
if [ "$ACS_NAME" == "" ] || [ "$ACS_NAME" == null ]; then
    echo "ERROR ::: Azure Cognitive Search is Not provided in admin secret"
    IS_ACS="N"
else
    echo "ERROR ::: Azure Cognitive Search ::: $ACS_NAME not found"
    # ACS_STATUS=`az search service show --name $ACS_NAME --resource-group $ACS_RESOURCE_GROUP | jq -r .status`
    ACS_STATUS=`az search service show --name $ACS_NAME --resource-group $ACS_RESOURCE_GROUP --query "[].status"`
    echo "$?"
    echo ">>>>>>>>>>>>>>>>>>> ACS_STATUS ::: $ACS_STATUS"
    
    if [ "$ACS_STATUS" != "" ] || [ "$ACS_STATUS" != null ] ; then
        IS_ACS="Y"
    echo "ASASASASA "
else
    echo "RTYRYTRYTRYTRYTRYTRT"
    fi
fi

if [ "$IS_ACS" == "N" ]; then
    echo "ERROR ::: Azure Cognitive Search is Not Configured. Need to Provision Azure Cognitive Search Before, NAC Provisioning."
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
    ##### RUN terraform init
    echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform init . . . . . . . . "
    COMMAND="terraform init"
    $COMMAND
    chmod 755 $(pwd)/*
    echo "INFO ::: CognitiveSearch provisioning ::: FINISH - Executing ::: Terraform init."
    ##### RUN terraform Apply
    echo "INFO ::: CognitiveSearch provisioning ::: BEGIN ::: Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
    COMMAND="terraform apply -auto-approve"
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
# exit 88888

##################################### START NAC Provisioning ###################################################################
create_Config_Dat_file 
install_NAC_CLI


NMC_VOLUME_NAME=$(echo "${TFVARS_FILE}" | rev | cut -d'/' -f 1 | rev |cut -d'.' -f 1)
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
### Download Provisioning Code from GitHub
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
pwd
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
echo "INFO ::: Copy TFVARS file to $(pwd)/${GIT_REPO_NAME}/${TFVARS_FILE}"
# cp "$NMC_VOLUME_NAME/${TFVARS_FILE}" $(pwd)/"${GIT_REPO_NAME}"/
cp "${TFVARS_FILE}" "${GIT_REPO_NAME}"/
cd "${GIT_REPO_NAME}"
pwd
ls
##### RUN terraform init
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
# exit 1
echo "INFO ::: NAC provisioning ::: FINISH - Executing ::: Terraform init."
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "
COMMAND="terraform apply -var-file=${TFVARS_FILE} -auto-approve"
# COMMAND="terraform validate"
$COMMAND
if [ $? -eq 0 ]; then
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
    else
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
        exit 1
    fi
##################################### END NAC Provisioning ###################################################################

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
echo "INFO ::: Total execution Time ::: $DIFF"
#exit 0

} || {
    END=$(date +%s)
	secs=$((END - START))
	DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
	echo "INFO ::: Total execution Time ::: $DIFF"
	exit 0
    echo "INFO ::: Failed NAC Povisioning" 

}
