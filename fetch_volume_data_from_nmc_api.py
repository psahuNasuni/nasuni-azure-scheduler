import shlex
import urllib.parse, json, subprocess
import urllib.request as urlrq
import ssl, os
import sys,logging
import requests
import re
from datetime import *

def create_share_data_json(data_json, volume_name):
    share_data_path = "/var/www/SearchUI_Web/share_data.json"

    if os.path.exists(share_data_path):
        with open(share_data_path, 'r') as share_data_file:
            share_data = json.load(share_data_file)
        
        if volume_name in share_data:
            share_data[volume_name] = data_json
        else:
            share_data[volume_name] = data_json
    else:
        share_data = {volume_name: data_json}
    
    with open(share_data_path, 'w') as share_data_file:
        json.dump(share_data, share_data_file, indent=4)


if len(sys.argv) < 6:
    print(
        'Usage -- python3 fetch_volume_data_from_nmc_api.py <ip_address> <username> <password> <volume_name> <web_access_appliance_address>')
    exit()

logging.getLogger().setLevel(logging.INFO)
logging.info(f'date={date}')

if not os.environ.get('PYTHONHTTPSVERIFY', '') and getattr(ssl, '_create_unverified_context', None):
    ssl._create_default_https_context = ssl._create_unverified_context

file_name, endpoint, username, password, volume_name, web_access_appliance_address = sys.argv

try:
    #logging.info(sys.argv)
    url = 'https://' + endpoint + '/api/v1.1/auth/login/'
    #logging.info(url)
    values = {'username': username, 'password': password}
    data = urllib.parse.urlencode(values).encode("utf-8")
    #logging.info(data)
    response = urllib.request.urlopen(url, data, timeout=5)
    #logging.info(response)
    result = json.loads(response.read().decode('utf-8'))
    #logging.info(result)

    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/\"'
    #logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    #logging.info(json_data)
    vv_guid = ''
    for i in json_data['items']:
        if i['name'] == volume_name:
            toc_file = open('nmc_api_data_root_handle.txt', 'w')
            toc_file.write(i['root_handle'])
            src_bucket = open('nmc_api_data_source_container.txt', 'w')
            src_bucket.write(i['bucket'])
            storage_account = open('nmc_api_data_source_storage_account_name.txt', 'w')
            storage_account.write(i['account_name'])
            v_guid = open('nmc_api_data_v_guid' + '.txt', 'w')
            v_guid.write(i['guid'])
            vv_guid = i['guid']
    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/filers/shares/\"'
    #logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    #logging.info(json_data)    

    share_url = open('nmc_api_data_external_share_url'+ '.txt', 'w')
    share_url.write(web_access_appliance_address)

    requests.packages.urllib3.disable_warnings()

    headers = {
        'Accept': 'application/json',
        'Authorization': 'Token {}'.format(result['token'])
    }
    try:
        r = requests.get('https://' + endpoint + '/api/v1.1/volumes/filers/shares/', headers = headers,verify=False)
    except requests.exceptions.RequestException as err:
        logging.error ("OOps: Something Else {}".format(err))
    except requests.exceptions.HTTPError as errh:
        logging.error ("Http Error: {}".format(errh))
    except requests.exceptions.ConnectionError as errc:
        logging.error ("Error Connecting: {}".format(errc))
    except requests.exceptions.Timeout as errt:
        logging.error ("Timeout Error: {}".format(errt)) 
    except Exception as e:
        logging.error('ERROR: {0}'.format(str(e)))
    
    share_data={}
    name_list=[]
    path_list=[]
    for i in r.json()['items']:
        if i['volume_guid'] == vv_guid and i['path']!='\\' and i['browser_access']==True:
            name_list.append(r""+i['name'].replace('\\','/'))
            path=r""+i['path']
            path=re.sub(r'\\+','/',path).strip('/')
            path_list.append(path)


    if len(name_list)==0 or len(path_list) == 0:
        data={"shares":[{"test-key-for-sharedata":"test-value-for-sharedata"}]}
        
        create_share_data_json(data, volume_name)

    else:
        data={"shares":[]}

        for name,value in zip(name_list,path_list):
            data["shares"].append({name:value})

        create_share_data_json(data, volume_name)

except Exception as e:
    print('Runtime Errors', e)
