import sys
import pprint
import shlex
import urllib.parse, json, subprocess
import urllib.request as urlrq
import ssl, os
import sys,logging
from datetime import *
import boto3

if not os.environ.get('PYTHONHTTPSVERIFY', '') and getattr(ssl, '_create_unverified_context', None):
    ssl._create_default_https_context = ssl._create_unverified_context

logging.getLogger().setLevel(logging.INFO)
logging.info(f'date={date}')
dash,username,password,endpoint=sys.argv
endpoint = endpoint.replace('\r', '')  # removing /r
print('Argument List:', str(sys.argv))
print('endpoint',endpoint)
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
    if(result):
        print('Token Generated')
    else:
        print('Token Not generated')
    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result['token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/\"'
    logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    if(json_data):
        print('Data Fetched')
    else:
        print('Data Not Fetched')
except Exception as e:
    print('Runtime Errors', e)
    exit(1)