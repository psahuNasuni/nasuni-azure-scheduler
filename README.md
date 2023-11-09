# Description

The NAC Scheduler extends the capabilities of the [Nasuni Analytics Connector](https://nac.cs.nasuni.com/) (NAC) by automatically exporting a volume in native object format, and then scheduling Azure services to run against the data on a periodic basis. For details of operating the Nasuni Analytics Connector, see [Nasuni Analytics Connector Azure](https://b.link/Nasuni_Analytics_Connector_AZURE).

The NAC Scheduler is a configuration script that:
* Deploys a Azure VM, that acts as a scheduler of the Nasuni Analytics Connector.
* Creates a custom Azure function for indexing data into an Azure Cognitive Search service.
* It also, creates a simple UI for accessing that service.
 
There is an AI powered information retrieval platform service that enable enterprise search to extract increasingly relevant and complete results. The NAC Scheduler currently supports: [Azure Cognitive Search Service](https://azure.microsoft.com/en-us/products/ai-services/cognitive-search#overview). Each deployment is started with a single command-line script that takes at most five arguments, and can deploy an entire system with one command.

[Cognitive Search Service](https://azure.microsoft.com/en-us/products/ai-services/cognitive-search#overview) is a cloud search service that gives developers infrastructure, APIs, and tools for building a rich search experience over private, heterogeneous content in web, mobile, and enterprise applications.

CognitiveSearch enables people to easily ingest (i.e. ingestion, parsing, and storing of textual content and tokens that populate a search index.), secure, search, aggregate, view, and analyze data. These capabilities are popular for use cases such as application search, log analytics, and more. With CognitiveSearch, people benefit from having an AI enabled Free-form text search that provide a secure, high-quality search and analytics suite with a rich roadmap of new and innovative functionality.

# Prerequisites

To install the NAC Scheduler, you need the following:

1. The [Azure command line tools](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), [jq](https://jqlang.github.io/jq/), wget, [Terraform](https://developer.hashicorp.com/terraform/tutorials/azure-get-started), [Python](https://www.python.org/downloads/), curl, dos2unix and [git] installed on a computer that is able to connect to the Azure Location in which you choose to deploy the NAC.
To install the above dependencies/prerequisite tools; you can execute the install_packages.sh file which is available in this repository.
```sh
./install_packages.sh
```
2. An Azure subscription with Administrator permissions.
3. ServicePrincipal with owner access . Example: nac_sp_user
4. Confirm that you have access to create and manage following services: 
    Azure Cognitive Search Service, Azure Function App, Application Configurations, Azure KeyVault, Azure Storage Account and Application Insights.    
5. Azure Storage account Container.
    Upload the NAC Volume key (.pgp file) in the "Volume key container". Upload to the [Analytics Connector] the encryption keys for the volume that you want to search, via the NAC’s Volume Encryption Key Export page. 
    
    If you are using encryption keys generated internally by the Nasuni Edge Appliance, you can export (download) your encryption keys with the Nasuni Edge Appliance. For details, see “Downloading (Exporting) Generated Encryption Keys” on page 379 of the [Nasuni Edge Appliance Administration Guide](https://b.link/Nasuni_Edge_Appliance_Administration_Guide). 
If you have escrowed your key with Nasuni and do not have it in your possession, contact Nasuni Support.
6. A Nasuni Edge Appliance with Web Access enabled on the volume that is being searched.

# Installation

## Quick Start

1. On your linux terminal, Sign in to Azure CLI using a service principal

2. Download the script NAC Scheduler from this repository, or clone this repository.

3. Make the NAC Scheduler script executable on your computer (i.e. Linux Jump box). 
    For example, you can run this command:
    ```sh 
        chmod 755 NAC_Scheduler.sh
    ```

4. Run the NAC Scheduler script with at least four arguments:
    * The name of the volume.
    * The name of the service to be integrated with (i.e. acs).
    * The frequency of the indexing (in minutes).
    * The name of the user input Vault used.
    * (Optional) The name of the KeyValue Pairs Text file, that contains the overridable static parameters for NAC. If you dont pass this parameters, it will take default values for NAC Execution.  
    
    For example, a command like this: (Here Volume name is Projects_volume_1)
    ```sh 
        ./NAC_Scheduler.sh Projects_volume_1 acs 300 my-secret-vault
    ```

    When the script has completed, you will see a URL.

## Detailed Instructions

1. #### Sign in to Azure CLI using a service principal
- Verify your logged in user with below command: 
    ```sh 
    az account show
    ``` 
    - Confirm that the output shows correct Service Principal App ID under section “user >> name” 
        Example: 	
        ```sh 
            “user” : {
                    “name” : “<<Your Service Principal Application ID>>”
                    . . . 
            }
        ```
    - Confirm that the output has “type” : “servicePrincipal” under section “user”
        Example: 
        ```sh
            “user” : {
                “name” : “<<Your Service Principal Application ID>>”
                “type” : “servicePrincipal”
            }
        ```
    - Verify the Microsoft Entra tenant ID.
        Example: 
        ```sh
            “tenantId” : “<<Your Microsoft Entra Tenant ID>>”
        ```
- Export the useful environment variables using below Syntax:
    ```sh
        export ARM_CLIENT_ID="<<Service Principal Application ID>>"  
        export ARM_CLIENT_SECRET="<<Service Principal Password>>" 
        export ARM_TENANT_ID="<<Microsoft Entra Tenant ID>>" 
        export ARM_SUBSCRIPTION_ID="<<Azure Subscription ID>>"
    ```
- Login to Azure from Azure CLI using Azure ServicePrincipal. You can use the below Syntax:
    ```sh
        az login --service-principal --tenant <Microsoft_Entra_Tenant_ID> --username <Service_Principal_Application_ID> --password <Service_Principal_password>
    ```

2. #### Download the NAC Scheduler script from this repository, or clone this repository.
    ```sh
        Example:  
            git clone https://github.com/psahuNasuni/nasuni-nac-scheduler.git -b nac_v1.0.7.dev6
    ```
3. #### Make the NAC Scheduler script executable on your local computer.
    Refer the step 3 of "**Quick Start**" 
4. #### Create secret Vault 
    If you have not created a KeyVault in the [Azure KeyVault], create one now using one of two methods:

    **Create via Azure Portal**
    
    1. Login to [Azure Portal](https://portal.azure.com/#home) with your subscription 
    2. On the portal Navigate to [Create a Key Vault](https://portal.azure.com/#create/Microsoft.KeyVault) page, provide the following information:
        - Name: provide a unique name.
        - Subscription: Choose a subscription.
        - Under Resource Group, choose Create new and enter a resource group name.
        - In the Location pull-down menu, choose a location.
        - Provide the other options as per your need. 
    click "**Create**" button.
    3. Create secrets or key value pairs with the following:

        Example: Vault Name = my-secret-vault
    
        |Sl No|Secret Key| Value (example)    | Notes   .    |
        |-----|----------|--------| ----------------    |
        |1|nmc-api-endpoint|10.1.1.2|Should be accessible to the resources created by this script.|
        |2|nmc-api-username|apiuser|Make sure that this API user has the following Permissions: "Enable NMC API Access" and "Manage all aspects of Volumes".  For details, see “Adding Permission Groups” on page 461 of the [Nasuni Management Console Guide](https://b.link/Nasuni_NMC_Guide).|
        |3|nmc-api-password|notarealpassword|Password for this user.|
        |4|product-key|XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX|Your product key can be generated on the [Nasuni Cloud Services page] in your Nasuni dashboard.|
        |5|web-access-appliance-address|10.1.1.1|Should be publicly accessible and include shares for the volume being searched.|
        |6|cred-vault|nac_user_cred_vault|Provide the User Credential Vault name. This is the Azure Key-Vault containing user name and password,   where; the user name must have owner access|
        |7|volume-key-container-url|    https://VolumeStorageContainer. blob.core.windows.net/key/XXXXX.pgp    |This is the parameter value created when you upload your pgp key file to the VolumeStorageContainer container. After uploading, follow below steps to get the volume-key-container-url: - Login to the Azure Portal and navigate to Microsoft_Azure_Storage. - Identify the VolumeKey Storage account - Navigate to Containers   - Click on the container name    - Click on the pgp file name     - Copy the URL under Properties|
        |8|pem-key-path|/home/my-folder/.ssh/mypemkey.pem|A pem key which is also stored as one of the [key pairs] in your Azure account. (NB: case matters. Make sure that the pem key in the pem-key-path has the same capitalization as the corresponding key in Azure)|
        |9|nac-scheduler-name|NAC_Scheduler_VM|(Optional) The name of the NAC Scheduler. If this variable is not set, the name defaults to "NAC_Scheduler"|
        |10|github-organization|nasuni-labs|(Optional) If you have forked this repository or are using a forked version of this repository, add that organization name here. All calls to github repositories will look within this organization|
        |11|azure-location|canadacentral|The Azure Region/Location, where you want to execute NAC|
        |12|azure-subscription|XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX|The Subscription ID, of your Azure Account|
        |13|use_private_ip|Y|(Optinal)If you want to provision the infrastructure in a Private subnet, add the instruction in with use_private_ip. All resources will be provisioned in the provided Private vNet, if the value passed as "Y". If this variable is not provided, the execution will happen in the Default Public Subnet.|
        |14|networking-resource-group|network-rg-XXXXX|This is the Azure Resource Group, where all network related resources will be provisioned.|
        |15|user-vnet-name|myuser_vnet|Provide the Specified vnet name. This vNet should reside in the networking resource group|
        |16|edgeappliance-resource-group|edgeappliance-rg-XXXXX|This is the Azure Resource Group, where the edge Appliance and source storage account resides. You can get this Resource Group by following steps: → Login to NMC → navigate to File Browser → select a volume → copy Account → search for the copied account in Azure portal to get the storage account → find the Resource Group  → This should be the edgeappliance-resource-group|
        |17|sp-secret|XXXXXXXXXXXXXXXXX|Provide the value of the Service Principal Id. All resources will be provisioned with Service Principal user. Follow the below stps to get the sp-secret from Azure Portal: - Login to the Azure Portal. Navigate to **Microsoft Entra ID** Click on **App registrations** from left menu, Search your SP (Example: pubnactest-sp), and Click on the **Certificates & secrets**. Value of sp-secret is the hidden Value in the table. If, you dont remember the avlue of the SP Secret, you can create one by **+ create**|
    4. After you have entered all the key value pairs, click **Next**.
    5. Choose a name for your key. Remember this name for when you run the initial script.  

    **Create a local file**

    1. Create a text file that contains the key/value pairs listed above.
    2. Do not use quotes for either the key or the value. For example: azure-location="canadacentral"
    3. Save this as a text file (for example, mysecret.txt) in the same folder as the NAC_Scheduler.sh script.

5. #### Provide NAC Parameters (Optional) 
- If you need to override any of the NAC parameters (as described in the Appendix: Automating Analytics Connector section of the [NAC Technical Documentation]), you can create a NAC variables file that lists the parameters you would like to change.

- Save this list of variables as a text file (for example, nacvariables.txt) in the same folder as the NAC_Scheduler.sh script.

6. #### Execute the script NAC_Scheduler.sh
    - ##### Scheduling NAC for Single Volume
        - Run the script with three to five arguments, depending on whether or not you have created a local secrets file or a NAC variables file. The order of arguments should be as follows:
            * The name of the volume.
            * The name of the service to be integrated with (see Services Available below).
            * The frequency of the indexing (in minutes).
            * The path to the secrets file created in Step 3 **Create via Azure Portal**, or the name of the User Input Vault generated in Step 3 **Create a local file**.
            * (OPTIONAL) The path to the NAC variables file.

        For example, a command to Execute the script NAC_Scheduler.sh with Four arguments would look like this:
        ```sh
            ./NAC_Scheduler.sh Projects_volume_1 acs 300 my-secret-vault
        ```

        For example, a command with all five arguments would look like this:
        ```sh
            ./NAC_Scheduler.sh Projects_volume_1 acs 300 my-secret-vault nacvariables.txt
        ```

   - ##### Scheduling NAC for Multiple Volume(s)
        - If, you want to schedule NAC for multiple volumes;
            - You need to create a secomd_volume specific secret Vault by following steps given in section **Create secret Vault**.
            - You need to execute the NAC_Scheduler.sh script as mentioned in above section **Scheduling NAC for Single Volume** from JumpBox Computer with the second_volume as first argument, and second_volume specific vault as Fourth argument.
                For example, a command like this:
                ```sh 
                    ./NAC_Scheduler.sh Projects_volume_2 acs 400 my-secret-vault_2
                    # Here, Volume name is Projects_volume_2,
                    # and Vault name is my-secret-vault_2
                ```
                
# Services Available

The NAC Scheduler currently supports the following services:

|Service Name|Argument Short Name|Description|What is deployed|
|------------|-------------------|-----------|----------------|
|Azure CognitiveSearch|acs|Automates the indexing of files created on a Nasuni volume.|1. NAC Scheduler (Azure VM) Instance (if not already deployed). 2. Azure CognitiveSearch service (if not already deployed). 3. Cron job to run terraform scripts to periodically create and destroy the NAC. 4. Azure Destination Container for preserving the short lived copy of the files in UniFS format 5. Azure function for indexing data exported by the NAC to the destination bucket(Azure Destination Container) and deleting the data after it has been indexed. 6. A simple Search UI available on the NAC Scheduler VM.|

# Getting Help

To get help, please [submit an issue] to this Github repository.

[Analytics Connector]: https://nac.cs.nasuni.com/launch.html
[Azure KeyVault]: https://azure.microsoft.com/en-in/products/key-vault
[git]: https://git-scm.com/downloads
[NAC Technical Documentation]: https://b.link/Nasuni_Analytics_Connector_AZURE
[Nasuni Cloud Services page]: https://account.nasuni.com/account/cloudservices/
[submit an issue]: https://github.com/nasuni-community-tools/sch-nac/issues
