# Create the infrastructure to provision NAC Scheduler
import os
import sys,logging
import json
from datetime import *
import ipaddress 
from ipaddress import IPv4Network

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

def available_ips_in_subnet(vnet_rg, vnet_name):
    """
    Returns the number of available ips
    """
    checking_mask=16
    max_ip = pow(2, (32-int(checking_mask))) -5

    used_ip_state='az network vnet show -g ' + vnet_rg + ' -n ' +  vnet_name + '| jq -r ".subnets[].ipConfigurations"'

    with os.popen(used_ip_state) as f:
        used_ip_state = f.readlines()

    search_term='"id":'
    used_ip_count=0

    for value in used_ip_state:
        if search_term in value :
            used_ip_count+=1
    
    available_ip = max_ip - int(used_ip_count)
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
    
    used_subnets.sort()

    return used_subnets

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


def get_next_subnet_address_in_vnet(last_address):
    """
    Create next subnet address in_vnet
    """
    split_last_add = last_address.split('.')
    third_octet = int(split_last_add[2]) + 1 # 26
    ### Need to handle the 255 condition
    split_last_add[2] = third_octet
    split_last_add[3] = 0
    
    # Group split octets
    next_address = split_last_add[0]
    
    for octet in range(1, len(split_last_add)):
        next_address += '.' + str(split_last_add[octet])
        
    return next_address

def get_next_available_range(current_subnet_state):
    current_subnet_state.sort()
    next_available_address = current_subnet_state[0]

    for subnet in current_subnet_state:
        if (next_available_address in current_subnet_state):
            next_available_address = get_next_subnet_address_in_vnet(subnet)
        else:
            break
    
    return next_available_address

def subnet_infrastructure(vnet_rg, vnet_name, subnet_mask, required_subnet_count):
    """
    Provision the Infrastructure
    """
    subnet_count = 0
    available_private_subnets = []
    # 10.23.0.0/16
    get_default_vnet_ip_add = get_default_vnet_ip(vnet_rg, vnet_name)
    # Get the count of available IPs in Vnet
    available_ips_in_vnet = available_ips_in_subnet(vnet_rg, vnet_name)
    if  available_ips_in_vnet > pow(2, (32-int(subnet_mask))): 
        net = IPv4Network(get_default_vnet_ip_add)
        # Change subnet mask to 28 as one subnet need atleast 16 IP address
        
        current_subnet_state = get_used_subnets(vnet_rg, vnet_name) # '10.23.25.0'
        # last_subnet = used_subnets[-1] # '10.23.25.0'
        while subnet_count < required_subnet_count:
            
            next_available_address=get_next_available_range(current_subnet_state)
            subnet_ip_range = next_available_address + '/24'

            net = IPv4Network(subnet_ip_range)
            for subnet_ip in net.subnets(new_prefix=int(subnet_mask)):
                available_private_subnets.append(str(subnet_ip))
                current_subnet_state.append(str(subnet_ip).split('/')[0])
                subnet_count += 1
                if subnet_count > ( required_subnet_count - 1 ):
                    break
            
    return available_private_subnets

if __name__ == "__main__":
    
    vnet_rg=sys.argv[1]
    vnet_name=sys.argv[2]
    subnet_mask=sys.argv[3]
    required_subnet_count = int(sys.argv[4])
    available_private_subnets = json.dumps(subnet_infrastructure(vnet_rg, vnet_name, subnet_mask, required_subnet_count)).replace(" ", "")
    print(available_private_subnets)