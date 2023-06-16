import shlex
import urllib.parse, json, subprocess
import urllib.request as urlrq
import ssl, os
import sys,logging
import requests
from datetime import *

if len(sys.argv) < 7:
    print(
        'Usage -- python3 fetch_nmc_api_23-8.py <ip_address> <username> <password> <volume_name> <rid> <web_access_appliance_address>')
    exit()

logging.getLogger().setLevel(logging.INFO)
logging.info(f'date={date}')

if not os.environ.get('PYTHONHTTPSVERIFY', '') and getattr(ssl, '_create_unverified_context', None):
    ssl._create_default_https_context = ssl._create_unverified_context

file_name, endpoint, username, password, volume_name, rid, web_access_appliance_address = sys.argv

try:
    logging.info(sys.argv)
    url = 'https://' + endpoint + '/api/v1.1/auth/login/'
    logging.info(url)
    values = {'username': username, 'password': password}
    data = urllib.parse.urlencode(values).encode("utf-8")
    logging.info(data)
    response = urllib.request.urlopen(url, data, timeout=5)
    logging.info(response)
    result = json.loads(response.read().decode('utf-8'))
    logging.info(result)

    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/\"'
    logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    logging.info(json_data)
    vv_guid = ''
    for i in json_data['items']:
        if i['name'] == volume_name:
            toc_file = open('nmc_api_data_root_handle.txt', 'w')
            toc_file.write(i['root_handle'])
            src_bucket = open('nmc_api_data_source_container.txt', 'w')
            src_bucket.write(i['bucket'])
            storage_account = open('nmc_api_data_source_storage_account_name.txt', 'w')
            storage_account.write(i['account_name'])
            v_guid = open('nmc_api_data_v_guid_' + rid + '.txt', 'w')
            v_guid.write(i['guid'])
            vv_guid = i['guid']
    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/filers/shares/\"'
    logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    logging.info(json_data)    
    # My Accelerate Test
    share_url = open('nmc_api_data_external_share_url_' + rid + '.txt', 'w')
    share_url.write(web_access_appliance_address)


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
            path_list.append(r""+i['path'].replace('\\',''))


    if len(name_list)==0 or len(path_list) == 0:
        logging.info('dict is empty')

        with open('nmc_api_v_share_name_data' + '.txt', 'w') as file:
            file.write("-")

        with open('nmc_api_v_share_path_data' + '.txt', 'w') as file:
            file.write("-")

    else:
        logging.info('dict has data'.format(name_list))
        logging.info('dict has data'.format(path_list))

        with open('nmc_api_v_share_name_data' + '.txt', 'w') as file:
            file.write(",".join(name_list))

        with open('nmc_api_v_share_path_data' + '.txt', 'w') as file:
            file.write(",".join(path_list))

except Exception as e:
    print('Runtime Errors', e)
