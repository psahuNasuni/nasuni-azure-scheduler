import unittest

from create_subnets.create_subnet_infra import *


class TestSubnet(unittest.TestCase):
    def test_available_ips_in_subnet(self):
        """
        Test that it can sum a list of integers
        """
        vnet_rg="nac-nmc-22-2-1"
        vnet_name="nac-nmc-22-2-1-vnet"
        subnet_name="default"
        subnet_mask="16"

        result = available_ips_in_subnet(vnet_rg, vnet_name, subnet_name, subnet_mask)

        self.assertGreater(result, 249)

    @remove_new_line
    def test_is_ip_available(self):
        """
        Test whether subnet is created 
        """
        vnet_rg="nac-nmc-22-2-1"
        vnet_name="nac-nmc-22-2-1-vnet"
        ip_address="10.23.6.0"
        result = is_ip_available(vnet_rg, vnet_name, ip_address)
        self.assertTrue(result)
    
    @remove_new_line
    def test_get_default_vnet_ip(self):
        """
        Test whether subnet is created 
        """
        vnet_rg="nac-nmc-22-2-1"
        vnet_name="nac-nmc-22-2-1-vnet"
        result = get_default_vnet_ip(vnet_rg, vnet_name)
        self.assertIsNotNone(result)
    
    def test_ip_generator(self):
        """
        Test whether subnet is created 
        """
        subnet_ip = "10.23.6.0"
        result = ip_generator(subnet_ip)
        self.assertIsInstance(result, list)
        
if __name__ == '__main__':
    unittest.main()