# Create the infrastructure to provision NAC Scheduler
import os
import sys,logging
import json
from datetime import *
import ipaddress 
from ipaddress import IPv4Network
from sortedcontainers import SortedDict

logging.getLogger().setLevel(logging.INFO)
logging.info(f'date={date}')

def remove_new_line(f):
    """
    Decorator to remove new line from result
    """
    def wrapper(*args, **kwargs):
        result = f(*args, **kwargs)
        result = result[0].replace("\n", "")
        return result
    return wrapper


def available_ips_in_subnet(vnet_rg, vnet_name, subnet_name, subnet_mask):
    """
    Returns the number of available ips
    """
    if subnet_name == 'default':
        subnet_mask = 16
    #max_ip=$((2 ** (32-$netmask)-5))
    max_ip = pow(2, (32-int(subnet_mask))) -5
    
    used_ip = 'az network vnet subnet show -g ' + vnet_rg + ' -n ' + subnet_name + ' --vnet-name ' + vnet_name + ' -o json | jq  ".ipConfigurations[].id" | wc -l'

    with os.popen(used_ip) as f:
        used_ip = f.readlines()
        used_ip = used_ip[0].replace("\n", "")

    available_ip = max_ip - int(used_ip)
    return available_ip


def create_subnet(vnet_rg, vnet_name, subnet_name, address_prefixes):
    """
    Provision subnet on Azure Vnet
    : address_prefixes "10.23.$i.0/24"
    """
    create_subnet = 'az network vnet subnet create -g ' + vnet_rg + ' --vnet-name ' + vnet_name + ' -n ' + subnet_name + ' --address-prefixes ' + address_prefixes + ' --delegations Microsoft.Web/serverFarms'

    with os.popen(create_subnet) as f:
        subnet_status = f.readlines()

    return subnet_status

# @remove_new_line
def is_ip_available(vnet_rg, vnet_name, ip_address):
    """
    Check if IP is available or not
    :param ip-address 10.23.1.0
    Create variable to track availabl IP count 
    """
    check_if_ip_available = 'az network vnet check-ip-address --ip-address ' + ip_address + ' --name ' + vnet_name + ' --resource-group ' + vnet_rg + ' | jq ".available"'
    
    with os.popen(check_if_ip_available) as f:
        ip_status = f.readlines()

    return ip_status

def get_used_subnets(vnet_rg, vnet_name):
    """
    Check if IP is available or not
    :param ip-address 10.23.1.0
    Create variable to track availabl IP count 
    """  
    used_subnets = 'az network vnet subnet list --resource-group ' + vnet_rg + ' --vnet-name ' + vnet_name + """ -o json | jq ".[].addressPrefix" | tr -d '"'"""
    
    with os.popen(used_subnets) as f:
        used_subnets = f.readlines()
        used_subnets = [subnet[:-4] for subnet in used_subnets]
    
    subnets_dict = {}
    # Sort the used subnets 
    for subnet in used_subnets:
        subnets_dict[int(subnet.split(".")[2])] = subnet

    subnets_dict = SortedDict(subnets_dict) 

    return subnets_dict[subnets_dict.iloc[-1]]

@remove_new_line
def get_default_vnet_ip(vnet_rg, vnet_name):
    """"
    Get the IP address of default subnet
    """
    default_ip = 'az network vnet show -g ' + vnet_rg + ' -n ' + vnet_name + """ -o json | jq ".addressSpace.addressPrefixes[0]" | tr -d '"' """

    with os.popen(default_ip) as f:
        default_ip = f.readlines()

    return default_ip

def ip_generator(subnet_ip):
    """
    Generate list of possible IPs
    :subnet_range '10.23.0.0/16'
    """
    return [str(ip) for ip in ipaddress.IPv4Network(subnet_ip)]

def get_subnet_name():
    """
    Return the next subnet available in the list
    """
    subnet_names = ['vnet-subnet-name-0', 'vnet-subnet-name-1', 'vnet-subnet-name-2', 'vnet-subnet-name-3', 'vnet-subnet-name-4', 'vnet-subnet-name-5', 'vnet-subnet-name-6', 'vnet-subnet-name-7', 'vnet-subnet-name-8', 'vnet-subnet-name-9', 'vnet-subnet-name-10', 'vnet-subnet-name-11', 'vnet-subnet-name-12', 'vnet-subnet-name-13', 'vnet-subnet-name-14', 'vnet-subnet-name-15']
    for subnet_name in subnet_names:
        yield subnet_name

def get_next_subnet_address_in_vnet(last_address):
    """
    Create next subnet address in_vnet
    """
    # 10.23.26.208
    # 10.23.26.0
    split_last_add = last_address.split('.')
    third_octet = int(split_last_add[2]) + 1 # 26
    ### Need to handle the 255 condition
    split_last_add[2] = third_octet
    split_last_add[3] = 0
    # Group split octets
    # next_address = ".".join(split_last_add) 
    next_address = split_last_add[0]
    
    for octet in range(1, len(split_last_add)):
        next_address += '.' + str(split_last_add[octet])
        
    return next_address


def subnet_infrastructure(vnet_rg, vnet_name, subnet_name, subnet_mask, required_subnet_count):
    """
    Provision the Infrastructure
    """
    subnet_count = 0
    available_private_subnets = []
    # 10.23.0.0/16
    get_default_vnet_ip_add = get_default_vnet_ip(vnet_rg, vnet_name)
    # Get the count of available IPs in Vnet
    available_ips_in_vnet = available_ips_in_subnet(vnet_rg, vnet_name, subnet_name, subnet_mask)
    if  available_ips_in_vnet > 288:
        net = IPv4Network(get_default_vnet_ip_add)
        # Change subnet mask to 28 as one subnet need atleast 16 IP address
        last_subnet = get_used_subnets(vnet_rg, vnet_name) # '10.23.25.0'
        # last_subnet = used_subnets[-1] # '10.23.25.0'
        while subnet_count < required_subnet_count:
            next_available_address = get_next_subnet_address_in_vnet(last_subnet)
            subnet_ip_range = next_available_address + '/24'
            net = IPv4Network(subnet_ip_range)
            for subnet_ip in net.subnets(new_prefix=int(subnet_mask)):
                available_private_subnets.append(str(subnet_ip))
                subnet_count += 1
                if subnet_count > ( required_subnet_count - 1 ):
                    break
            last_subnet = next_available_address

    return available_private_subnets

if __name__ == "__main__":
    # vnet_rg="nac-nmc-22-2-1"
    # vnet_name="nac-nmc-22-2-1-vnet"
    # subnet_name="default"
    # subnet_mask="28"
    vnet_rg=sys.argv[1]
    vnet_name=sys.argv[2]
    subnet_name=sys.argv[3]
    subnet_mask=sys.argv[4]
    required_subnet_count = int(sys.argv[5])
    available_private_subnets = json.dumps(subnet_infrastructure(vnet_rg, vnet_name, subnet_name, subnet_mask, required_subnet_count)).replace(" ", "")
    print(available_private_subnets)