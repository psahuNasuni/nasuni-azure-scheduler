import shlex
import urllib.parse, json, subprocess
import urllib.request as urlrq
import ssl, os
import sys,logging
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
            v_guid = open('nmc_api_data_source_storage_account_name.txt', 'w')
            v_guid.write(i['account_name'])
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
except Exception as e:
    print('Runtime Errors', e)
