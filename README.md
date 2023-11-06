# Description

The NAC Scheduler extends the capabilities of the [Nasuni Analytics Connector](https://nac.cs.nasuni.com/) (NAC) by automatically exporting a volume in native object format, and then scheduling AWS services to run against the data on a periodic basis. For details of operating the Nasuni Analytics Connector, see [Nasuni Analytics Connector AZURE](https://b.link/Nasuni_Analytics_Connector_AZURE).

The NAC Scheduler is a configuration script that:
* Deploys a Azure VM, that acts as a scheduler of the Nasuni Analytics Connector.
* Creates a custom Azure function for indexing data into an AZURE Cognitive Search service.
* It also, creates a simple UI for accessing that service.
 
There is an AI enabled Azure Cognitive Search service that the NAC Scheduler currently supports: [Azure Cognitive Search Service](https://azure.microsoft.com/en-us/products/ai-services/cognitive-search#overview). Each deployment is started with a single command-line script that takes at most five arguments, and can deploy an entire system with one command.

* [Cognitive Search Service](https://azure.microsoft.com/en-us/products/ai-services/cognitive-search#overview) is a cloud search service that gives developers infrastructure, APIs, and tools for building a rich search experience over private, heterogeneous content in web, mobile, and enterprise applications.

    CognitiveSearch enables people to easily ingest (i.e. ingestion, parsing, and storing of textual content and tokens that populate a search index.), secure, search, aggregate, view, and analyze data. These capabilities are popular for use cases such as application search, log analytics, and more. With CognitiveSearch, people benefit from having an AI enabled Free-form text search that provide a secure, high-quality search and analytics suite with a rich roadmap of new and innovative functionality.

# Prerequisites

To install the NAC Scheduler, you need the following:

1. The [command line Azure tools](https://learn.microsoft.com/en-us/cli/azure/), [jq], wget, Terraform, Python, curl, dos2unix and [git] installed on a computer that is able to connect to the region in which you choose to deploy the NAC.
2. An AWS account with API access stored in a profile named ‘nasuni’ on the computer on which the AWS tools are installed. In the profile, a region must be identified. To install that profile use: 
```sh
aws configure --profile nasuni
```
3. Upload to the [Analytics Connector] the encryption keys for the volume that you want to search, via the NAC’s Volume Encryption Key Export page. 
If you are using encryption keys generated internally by the Nasuni Edge Appliance, you can export (download) your encryption keys with the Nasuni Edge Appliance. For details, see “Downloading (Exporting) Generated Encryption Keys” on page 379 of the [Nasuni Edge Appliance Administration Guide](https://b.link/Nasuni_Edge_Appliance_Administration_Guide). 
If you have escrowed your key with Nasuni and do not have it in your possession, contact Nasuni Support.

4. An S3 bucket accessible to Lambda functions deployed by this project.

5. A Nasuni Edge Appliance with Web Access enabled on the volume that is being searched. That Edge Appliance should be deployed in the same region that had been selected in #2 above.

# Installation

## Quick Start

1. Download the script NAC Scheduler from this repository, or clone this repository.

2. Make the NAC Scheduler script executable on your local computer. For example, you can run this command:
```sh 
chmod 755 NAC_Scheduler.sh
```
3. Run the NAC Scheduler script with at least four arguments:
    * The name of the volume.
    * The name of the service to be integrated with (see Services Available below).
    * The frequency of the indexing (in minutes).
    * The name of the secrets manager used.
    
For example, a command like this:

```sh 
./NAC_Scheduler.sh Projects es 30 admin/nac/secret
```

When the script has completed, you will see a URL.

## Detailed Instructions

1. Download the NAC Scheduler script from this repository, or clone this repository.

2. Make the NAC Scheduler script executable on your local computer.

3. If you have not created a secret in the [AWS Secrets Manager], create one now using one of two methods:

    **Create via AWS Console**
    
    1. On the [AWS Secrets Manager] home page, click "**Store a New Secret**".
    2. On the next page, select "Other type of Secret".
    3. Create key value pairs for the following key/value pairs:
    
    |Key|Value (example)|Notes|
    |---|---------------|-----|
    |web_access_appliance_address|10.1.1.1|Should be publicly accessible and include shares for the volume being searched.|
    |destination_bucket|temporarybucket|See the fourth prerequisite described above.|
    |nmc_api_endpoint|10.1.1.2|Should be accessible to the resources created by this script.|
    |nmc_api_username|apiuser|Make sure that this API user has the following Permissions: "Enable NMC API Access" and "Manage all aspects of Volumes". For details, see “Adding Permission Groups” on page 461 of the [Nasuni Management Console Guide](https://b.link/Nasuni_NMC_Guide).|
    |nmc_api_password|notarealpassword|Password for this user.|
    |nac_product_key|XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX|Your product key can be generated on the [Nasuni Cloud Services page] in your Nasuni dashboard.|
    |volume_key|/nasuni/keyname.pgp-111111|This is the parameter value created by Nasuni when you upload your keys through the [Nasuni Cloud Services page]. After you are on the [Nasuni Cloud Services page], click **Launch**. On the next page, choose "Run in AWS". On the next page, click **Get Started**. Select a region and make sure it is the same region that you set when you created the AWS default profile in the Prerequisites above. After accepting the Terms of Service, click **Continue**. You are then prompted to upload keys. (**Note**: Key names cannot have spaces in the names.) Upload the keys, and you receive a path back in the format listed here. |
    |volume_key_passphrase|mysecretpassphrase|Use the passphrase associated with the keys|
    |pem_key_path|/home/johndoe/.ssh/mypemkey.pem|A pem key which is also stored as one of the [key pairs] in your AWS account. (NB: case matters. Make sure that the pem key in the pem_key_path has the same capitalization as the corresponding key in AWS)|
    |nac_scheduler_name|My_NAC_Scheduler|(Optional) The name of the NAC Scheduler. If this variable is not set, the name defaults to "NAC_Scheduler"|
    |github_organization|nasuni-labs|(Optional) If you have forked this repository or are using a forked version of this repository, add that organization name here. All calls to github repositories will look within this organization|
    |use_private_ip|Y|(Optinal)If you want to provision the infrastructure in a Private subnet, add the instruction in with use_private_ip. All resources will be provisioned in the provided Private , if the value passed as "Y". If this variable is not provided, the execution will happen in the Default VPC's default Public Subnet.|
    |user_subnet_id|sunbet-XXXXXXXXXXX|(Optinal)If you want to provision the infrastructure in a Private subnet, add the Private Subnet ID of your choice as user_subnet_id . All resources will be provisioned in the provided Private subnet. If this variable is not provided, the execution will happen in the Default VPC Subnet.|
    4. After you have entered all the key value pairs, click **Next**.
    5. Choose a name for your key. Remember this name for when you run the initial script.  

    **Create a local file**

    1. Create a text file that contains the key/value pairs listed above.
    2. Do not use quotes for either the key or the value. For example: destination_bucket=temporarybucket
    3. Save this as a text file (for example, mysecret.txt) in the same folder as the NAC_Scheduler.sh script.

4. If you need to override any of the NAC parameters (as described in the Appendix: Automating Analytics Connector section of the [NAC Technical Documentation]), you can create a NAC variables file that lists the parameters you would like to change.

5. Save this list of variables as a text file (for example, nacvariables.txt) in the same folder as the NAC_Scheduler.sh script.

6. Run the script with three to five arguments, depending on whether or not you have created a local secrets file or a  NAC variables file. The order of arguments should be as follows:
    * The name of the volume.
    * The name of the service to be integrated with (see Services Available below).
    * The frequency of the indexing (in minutes).
    * The path to the secrets file created in Step 3 **Create via AWS Console**, or the name of the secrets file generated in Step 3 **Create a local file**.
    * (OPTIONAL) The path to the NAC variables file.

For example, a command with all five arguments would look like this:

```sh
./NAC_Scheduler.sh Projects es 30 mysecret.text nacvariables.txt
```
# Services Available

The NAC Scheduler currently supports the following services:

|Service Name|Argument Short Name|Description|What is deployed|
|------------|-------------------|-----------|----------------|
|AWS OpenSearch|es|Automates the indexing of files created on a Nasuni volume.|1. NAC Scheduler EC2 Instance (if not already deployed). 2. OpenSearch service and domain (if not already deployed). 3. Cron job to run terraform scripts to periodically create and destroy the NAC. 4. Lambda function for indexing data exported by the NAC to the S3 destination bucket described in the pre-requisite and deleting the data after it has been indexed. 5. A simple Search UI available on the NAC Scheduler.|
|AWS Kendra|kendra|Automates the indexing of files created on a Nasuni volume.|See AWS OpenSearch. |
|AWS SageMaker Model Building Pipelines|pipeline|Automates the ingestion of data into any SageMaker Model Building pipeline workflow that has an S3 bucket as the source of data in the first process step.|1. NAC Scheduler EC2 Instance (if not already deployed). 2. Cron job to run terraform scripts to periodically create and destroy the NAC.|

# Getting Help

To get help, please [submit an issue] to this Github repository.

[Analytics Connector]: https://nac.cs.nasuni.com/launch.html
[AWS Secrets Manager]: https://console.aws.amazon.com/secretsmanager/home
[command line AWS tools]: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
[git]: https://git-scm.com/downloads
[key pairs]: https://console.aws.amazon.com/ec2/v2/home#KeyPairs:
[NAC Technical Documentation]: https://b.link/Nasuni_Analytics_Connector_AWS
[Nasuni Cloud Services page]: https://account.nasuni.com/account/cloudservices/
[submit an issue]: https://github.com/nasuni-community-tools/sch-nac/issues
