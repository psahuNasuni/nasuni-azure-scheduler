# 1- Create a function that takes the values of the Keys of _source section, as parameter(s)
from http import server
import json
import os
import os.path
import sys

def is_file_exist(tracker_dir, filename):
    """
    Check if file exist or not
    """
    if os.path.isfile(tracker_dir + filename):
        print ("Tracker JSON exist: " + tracker_dir + filename)
        return True
    else:
        print ("Tracker JSON Dose exist: " + tracker_dir + filename)
        return False
   
def add_source(acs_url, acs_request_url, default_url, frequency, user_secret, created_by, created_on, volume, service):
    """
    Add _source information 
    """
    _source = {}
    _source["acs_url"] = acs_url
    _source["acs_request_url"] = acs_request_url
    _source["default_url"] = default_url
    _source["frequency"] = frequency
    _source["user_secret"] = user_secret
    _source["created_by"] = created_by
    _source["created_on"] = created_on
    _source["volume"] = volume
    _source["service"] = service
    return _source

def add_NAC_activity(most_recent_run, current_state, latest_toc_handle_processed):
    """
    Add NAC_activity information
    """
    _NAC_activity = {}
    _NAC_activity["most_recent_run"] = most_recent_run
    _NAC_activity["current_state"] = current_state
    _NAC_activity["latest_toc_handle_processed"] = latest_toc_handle_processed
    return _NAC_activity

def volume_tracker(volume, service, volume_tracker):
    """
    volume_tracker: Going to create the volume json file with service names
    """
    if volume in volume_tracker.keys():
        volume_tracker[volume].append(service)
        # Keep Unique Values in list as there should not be same Search service on same volume
        volume_tracker[volume] = list(set(volume_tracker[volume]))      
    else:
        volume_tracker[volume]=[]
        volume_tracker[volume].append(service)
    print(volume_tracker)
    return volume_tracker

def service_tracker(volume, service, service_tracker):
    """
    service_tracker: Going to create the search json file with volume names
    """
    if service in service_tracker.keys():
        service_tracker[service].append(volume)
        # Keep Unique Values in list as there should not be same Search service on same volume
        service_tracker[service] = list(set(service_tracker[service]))   
    else:
        service_tracker[service]=[]
        service_tracker[service].append(volume)
    return service_tracker

def combined_tracker_UI(acs_url, acs_request_url, default_url, frequency, user_secret, created_by, created_on, volume, service, most_recent_run, current_state, latest_toc_handle_processed, nac_scheduler_name):
    """
    tracker_UI: Going to create the dynamic json file
    """ 
    integration_name = volume + "_" + service
    tracker_json_filename = nac_scheduler_name + "_tracker.json"

    if is_file_exist(tracker_dir, tracker_json_filename):
        # Load the integration json file
        with open(tracker_dir + tracker_json_filename, "r") as file:
            tracker_json = json.load(file)
            file.close()
        # print(tracker_json)
        # Update the INTEGRATIONS
        if integration_name in tracker_json["INTEGRATIONS"].keys():
            # Change only _NAC_Activity
            tracker_json["INTEGRATIONS"][integration_name]["_NAC_activity"] = add_NAC_activity(most_recent_run, current_state, latest_toc_handle_processed)
        else: #Add new volume_service_name entry to the Integration json
            tracker_json["INTEGRATIONS"][integration_name] =  {}
            tracker_json["INTEGRATIONS"][integration_name]["_source"] = {}
            tracker_json["INTEGRATIONS"][integration_name]["_NAC_activity"] = {}
            tracker_json["INTEGRATIONS"][integration_name]["_source"] = add_source(acs_url, acs_request_url, default_url, frequency, user_secret, created_by, created_on, volume, service)
            # tracker_json["INTEGRATIONS"][integration_name]["_source"] = add_source(acs_url, default_url, frequency, user_secret, created_by, created_on, volume, service)
            tracker_json["INTEGRATIONS"][integration_name]["_NAC_activity"] = add_NAC_activity(most_recent_run, current_state, latest_toc_handle_processed)
        
        # Update the VOLUMES
        tracker_json["VOLUMES"] = volume_tracker(volume, service, tracker_json["VOLUMES"])
        # Update the SERVICES
        tracker_json["SERVICES"] = service_tracker(volume, service,tracker_json["SERVICES"])
    else: # If tracker json file is not exist
        tracker_json = {"INTEGRATIONS":{}}
        tracker_json["INTEGRATIONS"][integration_name] =  {}
        tracker_json["INTEGRATIONS"][integration_name]["_source"] = {}
        tracker_json["INTEGRATIONS"][integration_name]["_NAC_activity"] = {}
        tracker_json["INTEGRATIONS"][integration_name]["_source"] = add_source(acs_url, acs_request_url, default_url, frequency, user_secret, created_by, created_on, volume, service)
        # tracker_json["INTEGRATIONS"][integration_name]["_source"] = add_source(acs_url, default_url, frequency, user_secret, created_by, created_on, volume, service)
        tracker_json["INTEGRATIONS"][integration_name]["_NAC_activity"] = add_NAC_activity(most_recent_run, current_state, latest_toc_handle_processed)
        tracker_json["VOLUMES"] = {}
        tracker_json["VOLUMES"] = volume_tracker(volume, service, tracker_json["VOLUMES"])
        tracker_json["SERVICES"] = {}
        tracker_json["SERVICES"] = service_tracker(volume, service, tracker_json["SERVICES"])

    tracker_json = json.dumps(tracker_json)
    print("Tracker Json: " + tracker_json)
    with open(tracker_dir + tracker_json_filename, "w") as file:
        file.write(tracker_json)
        file.close()
    return tracker_json


if __name__ == '__main__':
    tracker_dir = "/var/www/Tracker_UI/docs/"
    try:
        if not os.path.exists(tracker_dir):
            os.makedirs(tracker_dir)
    except OSError as e:
        print("Exception while creating directory: " + str(e))

    acs_url = sys.argv[1]
    acs_request_url = sys.argv[2]
    default_url = sys.argv[3]
    frequency = sys.argv[4]
    user_secret = sys.argv[5]
    created_by =  sys.argv[6]
    created_on = sys.argv[7]
    volume = sys.argv[8]
    service = sys.argv[9]
    most_recent_run = sys.argv[10]
    current_state = sys.argv[11]
    latest_toc_handle_processed = sys.argv[12]
    nac_scheduler_name = sys.argv[13]
    print("Tracker Json ::: Execution Started")
    tracker_json = combined_tracker_UI(acs_url, acs_request_url, default_url, frequency, user_secret, created_by, created_on, volume, service, most_recent_run, current_state, latest_toc_handle_processed, nac_scheduler_name)
    