{#-MACROS #}
{% set dsf_utils_folder = 'dsf_utils' %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import logging_item with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import logging_salt with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import nap_time with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import sync_all_devices with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import sync_runners with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import sync_all_master with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import check_state with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import requirement_state_update_device_status with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import set_update_request_json with context %}
{%-from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros.sls' import set_update_status with context %}


{#-used by check_states() macro to define the event tag #}
{% set cap_category = 'request_approval' %}

{#- Globals variables #}
{% set globals = {} %}

{#-Saving calling arguments to include it in the approval payload for internal use #}
{% set orch_info_update_request = { 'orch_state': sls, 'pillar': pillar } %}

{#-Pillar variables required by DSF orch #}
{% set device = salt['pillar.get']('device', None) %}
{#- 
   Set to lower() to match folder salt://ems/
   Set to upper() when comparing to devices_allowed[] list
#}
{% set device = device.lower() if device else None %}
{% set version = salt['pillar.get']('version', None) %}


{#-gathering miscellaneous data required for orchestration processing  #}
{%-set master_id = salt['config.get']('id') %}
{%-set start_time = None|strftime("%Y%m%d-%H%M%S") %}
{%-do globals.update({'exec_id': start_time}) %}
{%-set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{#-Any better location for this file ?#}
{%-set master_logging_file = '/var/log/salt/salt-dsf-' ~ master_id ~ '_' ~ start_time ~ '_' ~ version ~ '_' ~ device ~ '.log' %}
{%-do globals.update({'master_logging_file': master_logging_file}) %}

{#-Bail out the orchestration if device or version are not present #}
{% if not device or not version %}
{%-  do salt['log.error'](">>>> DSF %s: ORCH START FAILED due device or version not present in pillar. Logging file: %s" % ('N/A', master_logging_file)) %}
{%-  set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-  set logging_line = '{"TYPE": "ERROR", "ACTION": "ORCH START FAILED due device or version not present in pillar", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{   logging_item(master_logging_file, logging_line)}}
device_or_version_not_present:
  test.configurable_test_state:
    - changes: False
    - result: False
    - comment: |
        device or version not present in pillar
        device: {{ device }}
        version: {{ version }}
    - failhard: True
{% endif %}


{#-Bail out the orchestration if requirements.yaml  or options.yaml file are not present #} 
{% if (device and version) and 
     (
      not salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'requirements.yaml')) or
      not salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'options.yaml')) 
     ) %}
{%-  do salt['log.error'](">>>> DSF %s: ORCH START FAILED due requirements file not found, check values provided for device: %s and version: %s. Logging file: %s" % (slspath.split('/')[1], device, version, master_logging_file)) %}
{%-  set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-  set logging_line = '{"TYPE": "ERROR", "ACTION": "ORCH START FAILED due required YAML files are not present, check values provided for device: %s and version: %s", "TIMESTAMP": "%s", "ID": "%s"}' %(version, device, timestamp, master_id) %}
{{   logging_item(master_logging_file, logging_line)}}
requirements_file_not_found:
  test.configurable_test_state:
    - changes: False
    - result: False
    - comment: |
        Required YAML files (requirements.yaml, options.yaml) not present under {{ device | path_join(version, device, 'yaml') }}
        device: {{ device }}
        version: {{ version }}
    - failhard: True
{% endif %}


{#-Import device requirements and options yaml and merge with pillar custom_requirements if available #}
{% set requirements_map = None %}
{% if (device and version) and 
     salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'requirements.yaml')) and
     salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'update_content.yaml')) and
     salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'options.yaml')) and
     salt['slsutil.file_exists'](device | path_join(version, device, 'yaml', 'order.yaml'))
%}
{%-  import_yaml device | path_join(version, device, 'yaml', 'requirements.yaml') as requirements -%}
{%-  import_yaml device | path_join(version, device, 'yaml', 'update_content.yaml') as update_content -%}
{%-  import_yaml device | path_join(version, device, 'yaml', 'options.yaml') as options -%}
{%-  import_yaml device | path_join(version, device, 'yaml','order.yaml') as order -%}

{%-  set order_map = salt['pillar.get']('order', default=order, merge=True) -%}
{%-  do requirements.update(options) %}
{%-  do requirements.update(order_map) %}
{%-  do requirements.update(update_content) %}
{%-  set requirements_map = salt['pillar.get']('custom_requirements', default=requirements, merge=True) -%}
{%   do globals.update({'requirements_map': requirements_map | default({})}) %}

{%   do globals.update({'update_id': requirements_map['update_content']['ID']}) %}
{#-  Add dsf_version to internal payload #}
{%-  set dsf_version = requirements_map['dsf_version'] %}
{%-  do orch_info_update_request.update({'dsf_version': dsf_version}) %}

#    Sync modules
{%   if requirements_map['sync_all_devices'] %}
{{     sync_all_devices() }}
{%   endif %}
{%   if requirements_map['sync_runners'] %}
{{     sync_runners() }}
{%   endif %}
{%   if requirements_map['sync_all_master'] %}
{{     sync_all_master() }}
{%   endif %}

# Force a grains refresh on all devices
{% do salt['saltutil.runner']('dsf_cap.refresh_grains') %}

{#-  Logging: Orch start #}
{%-  do salt['log.info'](">>>> DSF %s: ORCH START: %s" % (dsf_version, master_logging_file)) %}
{%-  set logging_line = '{"TITLE": "DSF Logging %s", "TIMESTAMP": "%s", "ID": "%s"}' %(master_logging_file, timestamp, master_id) %}
{{   logging_item(master_logging_file, logging_line)}}
event_ORCH_START:
  salt.runner:
    - name: event.send
    - tag: DSF_orch/{{ cap_category }}/ORCH_STARTED
    - data:
        dsf_version: {{ dsf_version | default(None) }}
        dsf_sls: {{ sls.replace('/','.') }}
        device: {{ device | default(None) }}
        version: {{ version | default(None) }}
        master_logging_file: {{ master_logging_file | default(None) }}
        requirements_map: {{ requirements_map | default(None) }}
        order_map: {{ order_map | default(None) }}


nap_time_logging_dsf_start:
  salt.runner:
    - name: test.sleep
    - s_time: {{ requirements_map['nap_times']['dsf_start'] }}

{#-  Update runners if sync_runners if requirements.yaml #}
{%   if requirements_map['sync_runners']%}
update_runners:
  salt.runner:
    - name: saltutil.sync_runners
{%   endif %}

{#- Checking received pillar data to initiate the work #}
{%   if device and version %}



{%   else %}
{%-    do salt['log.error'](">>>> DSF %s: ORCH Pillar variables check FAILED: %s" % (dsf_version, master_logging_file)) %}
{%-    set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-    set logging_line = '{"TYPE": "ERROR", "ACTION": "DSF_pillar_missing", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{     logging_item(master_logging_file, logging_line)}}
device_version_FAILED:
  test.configurable_test_state:
    - changes: False
    - result: False
    - comment: |
        Missing required pillar values, aborting process immediately
        device: {{ device }}
        version: {{ version }}
    - failhard: True
{# QUESTION: Should this failure trigger any action/notification ? #}
{%   endif %}

{% endif %}

{% if requirements_map %}
{{   nap_time(requirements_map['nap_times']['post_pillar_checks']) }}
{% endif %}



{#- Continue only if pillar checks are ok#}
{#- REF: START CONTROL POINT 1#}
{% if device and version and requirements_map %}
{%   if device.upper() in devices_allowed and version in versions_allowed %}
{#-    Check use of requirements in requirements.yaml #}
{%     if requirements_map['use_requirements'] %}
{%-      do salt['log.info'](">>>> DSF %s: ORCH Using requirements map" % (dsf_version)) %}
{%-      set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-      set logging_line = '{"TYPE": "INFO", "ACTION": "DSF_requirements_usage_True", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{       logging_item(master_logging_file, logging_line)}}
{%       if 'custom_requirements' in pillar %}
{%-        set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-        set logging_line = '{"TYPE": "INFO", "ACTION": "DSF_requirements_using_custom_requirements", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{         logging_item(master_logging_file, logging_line)}}
{%-      endif %}


{#-      Add approval_tgt and approval_tgt_type to globals
         resolve tgt_type and generate proper approval_tgt based on tgt_type,
         including list with globals resolution and removal of white spaces
#}
{%-      do globals.update({'approval_tgt': requirements_map['approval_tgt']}) %}
{%-      set approval_tgt =  globals.get('approval_tgt', None) %}
{%-      do globals.update({'approval_tgt_type': salt['saltutil.runner']('dsf_cap.tgt_type', arg=[approval_tgt])}) %}
{%       if globals.get('approval_tgt_type', 'glob') == 'list' %}
{%-        do globals.update({'approval_tgt': approval_tgt.replace(" ","")}) %}
{%-        set approval_tgt =  globals.get('approval_tgt', None) %}
{%         if globals.get('approval_tgt_type', None) == 'list' and '*' in approval_tgt %}
{%           set tgt = salt['saltutil.runner']('dsf_cap.resolve_glob_list',arg=[tgt]) %}
{%-          do globals.update({'approval_tgt': tgt}) %}
{%-          set approval_tgt =  globals.get('approval_tgt', None) %}
{%         endif %}
{%       endif %}
{%-      do globals.update({'approval_tgt_os': salt['saltutil.runner']('dsf_cap.resolve_tgt_os', arg=[approval_tgt])}) %}
{%-      set approval_tgt_os = globals.get('approval_tgt_os', None) %}  


{#-      logging_filepath (to be used by the tgt minion) to track progress #}
{%       set logging_filepath = requirements_map['logging_filepath'] %}
{#-      Fix "\\\\" in Windows path #}
{%-      set windows_fix_path = logging_filepath['Windows'].replace("\\\\","\\")%}
{%-      do logging_filepath.update({'Windows': windows_fix_path}) %}
{%-      do globals.update({'logging_filepath': logging_filepath}) %}

REQUIREMENTS_USE_TRUE:
  test.configurable_test_state:
    - changes: False
    - result: True
    {% if 'custom_requirements' in pillar %}
    - warnings: Using custom requirements map
    {% endif %}
    - comment: |
        Use requirements yaml
        {{ requirements_map | tojson }}
{%     else %}
{%-      do salt['log.warning'](">>>> DSF %s: ORCH NOT Using requirements map" % (dsf_version)) %}
{%-      set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-      set logging_line = '{"TYPE": "WARNING", "ACTION": "DSF_requirements_usage_False", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{       logging_item(master_logging_file, logging_line)}}
REQUIREMENTS_USE_FALSE:
  test.configurable_test_state:
    - changes: False
    - result: True
    - warnings: Not using requirements map
    - comment: Not using requirements map
{%     endif %}
{#-    END OF - Check use of requirements in requirements.yaml #}


{#-    Set order of execution for device from order.yaml #}
{%-    do salt['log.info'](">>>> DSF %s: ORCH Setting up order: %s" % (dsf_version,order_map[device])) %}
{%-    set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-    set logging_line = '{"TYPE": "INFO", "ACTION": "DSF_set_order %s", "TIMESTAMP": "%s", "ID": "%s"}' %(order_map[device],timestamp,master_id) %}
{{     logging_item(master_logging_file, logging_line)}}

{#-    Define expected target devices to execute the update on #}
{%     set expected_devices = salt['saltutil.runner']('dsf_cap.expected_devices',  tgts=order_map[device]) %}
{%-    do salt['log.info'](">>>> DSF %s: ORCH expected_devices: %s" % (dsf_version, expected_devices)) %}
{%-    set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-    set logging_line = '{"TYPE": "INFO", "ACTION": "DSF_expected_devices %s", "TIMESTAMP": "%s", "ID": "%s"}' %(expected_devices,timestamp,master_id) %}
{{     logging_item(master_logging_file, logging_line)}}

{#-    Set approval payload #}
{%-    set now = None | strftime("%Y-%m-%d %H:%M:%S") -%}
{%     set update_payload = {} %}
{%-    do update_payload.update({'device': device}) %}
{%-    do update_payload.update({'version': version}) %}
{%-    do update_payload.update({'order': order[device]}) %}
{%-    do update_payload.update({'internal': {'orch_info': {'logging_file': master_logging_file, 'update_request': orch_info_update_request, 'master_id': master_id, 'exec_id': globals.get('exec_id', None)}}}) %}
{%-    do globals.update({'updates_file': requirements_map['updates_file']}) %}
{%-    do update_payload.update({'updates_file': globals.get('updates_file', None)}) %}
{%-    do update_payload.update({'update_content': requirements_map['update_content']}) %}

{#-    Add devices status to payload #}
{%-    do update_payload['internal'].update({'devices': {}}) %}
{%-    for device_id in expected_devices['up'] %}
{%-      do update_payload['internal']['devices'].update({device_id: {}}) %}
{%-      do update_payload['internal']['devices'][device_id].update({'device_status': 'up'}) %}
{%-      do update_payload['internal']['devices'][device_id].update({'update_status': [now ~ ' - UP, pending requisites check']}) %}
update_device_status_{{ device_id }}:
  salt.runner:
    - name: dsf_cap.data_add_device_update_status
    - exec_id: {{ globals.get('exec_id', None) }}
    - update_id: {{ requirements_map['update_content']['ID'] }}
    - device_id: '{{ device_id }}'
    - message: 'OK - UP, pending requisites check'
{%-    endfor %}
{%-    for device_id in expected_devices['down'] %}
{%-      do update_payload['internal']['devices'].update({device_id: {}}) %}
{%-      do update_payload['internal']['devices'][device_id].update({'device_status': 'down'}) %}
{%-      do update_payload['internal']['devices'][device_id].update({'update_status': [now ~ ' - DOWN, pending requisites check']}) %}
update_device_status_{{ device_id }}:
  salt.runner:
    - name: dsf_cap.data_add_device_update_status
    - exec_id: {{ globals.get('exec_id', None) }}
    - update_id: {{ requirements_map['update_content']['ID'] }}
    - device_id: '{{ device_id }}'
    - message: 'FAIL - DOWN, pending requisites check'
{%-    endfor %}


{%-    do globals.update({'update_payload': update_payload}) %}
{%     do globals.update({'approver_updates_file': globals.get('updates_file', []).get(globals.get('approval_tgt_os', None)).replace("\\\\","\\")}) %} #}

{#-    Send new update to JSON file with status 'initializing', internal devices status info not included #}
{{ set_update_request_json(
        device=device,
        device_id=globals.get('approval_tgt', None),
        caller=globals.get('approval_tgt', None),
        tgt_type=globals.get('approval_tgt_type', 'glob'),
        updates_file=globals.get('approver_updates_file', None),
        dsf_version=dsf_version,
        version=version,
        master_id=master_id,
        master_logging_file=globals.get('master_logging_file', None),
        update_id=globals.get('update_id', None),
        logging_filepath=globals.get('logging_filepath', None),
        exec_id=globals.get('exec_id', None),
        update_payload=globals.get('update_payload', None),
        track_progress=False,
        update_actions_updates_file=False,
        cap_category=cap_category
      )
}}

{%   set approver_updates_file = globals.get('updates_file', []).get(globals.get('approval_tgt_os', None)).replace("\\\\","\\") %}

{#-  Set update status to initializing #}  
{%   set update_status = 'initializing' %}
{{   set_update_status(
        status=update_status,
        device=device,
        device_id=globals.get('approval_tgt', None),
        caller=globals.get('approval_tgt', None),
        tgt_type=globals.get('approval_tgt_type', 'glob'),
        updates_file=globals.get('approver_updates_file', None),
        dsf_version=dsf_version,
        version=version,
        master_id=master_id,
        master_logging_file=globals.get('master_logging_file', None),
        update_id=globals.get('update_id', None),
        logging_filepath=globals.get('logging_filepath', None),
        exec_id=globals.get('exec_id', None),
        update_payload=globals.get('update_payload', None),
        track_progress=False,
        update_actions_updates_file=False,
        cap_category=cap_category,
        requisites={'require': ['salt: set_update_request_json']}
      )
}}
{% do globals.update({'update_status': update_status}) %}


{{     nap_time(requirements_map['nap_times']['pre_requirements_checks']) }}


{%-    for device_id in expected_devices['up'] %}
{#-      Execute requirements for each device #}
{%       if requirements_map['use_requirements'] %}
{#-        Execute requirements check states following defined order_map for targeting #}
{%         for tgt in order_map[device] %}
{%           set tgt_loop = loop %}
{#-          Check what tgt_type based on match pattern #}
{%           set tgt_type = salt['saltutil.runner']('dsf_cap.tgt_type', arg=[tgt]) %}
{%           if tgt_type == 'list' %}
{#-            Removing white spaces #}
{%             set tgt = tgt.replace(" ","") %}
{#-            Resolve and expand list with glob '*' #}
{%             if tgt_type == 'list' and '*' in tgt %}
{%               set tgt = salt['saltutil.runner']('dsf_cap.resolve_glob_list',arg=[tgt]) %}
{%             endif %}
{%           endif %}
{%-          do salt['log.info'](">>>> DSF %s: ORCH Setting up tgt_type for requirements execution: %s" % (dsf_version, tgt_type)) %}
{%-          set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-          set logging_line = '{"TYPE": "INFO", "ACTION": "DSF set_tgt_type for requirements execution: %s", "TIMESTAMP": "%s", "ID": "%s"}' %(tgt_type,timestamp,master_id) %}
{{           logging_item(master_logging_file, logging_line)}}

{#-          For each tgt, execute the states as listed in requirements_map['states'] #}
{%           for _state in requirements_map['states'] %}
{%             for state, state_payload in _state.items() %}
{#-              search for state under salt://<device>/<version>/ and salt://<utils>/<version> #}
{%-              if salt['slsutil.file_exists']([[device, version, device, 'states', state] | join('/') | replace('.','/'), 'sls'] | join('.')) %}
{%-                set execute_state = True %}
{%-                set requirement_sls = [device, version, device, 'states', state] | join('.') %}
{%-              elif salt['slsutil.file_exists']([[device, version, requirements_map.get('utils_folder', 'utils'), state] | join('/') | replace('.','/'), 'sls'] | join('.')) %}
{%-                set execute_state = True %}
{%-                set requirement_sls = [ device, version, requirements_map.get('utils_folder', 'utils'), state] | join('.') %}
{%-              else %}
{%-                set execute_state = False %}
{%-                set requirement_sls = 'STATE NOT FOUND ' ~ state %}
{%-              endif %}
{%-              set requirement_state_name = tgt_loop.index ~ '_' ~ state ~ '_' ~ device_id ~ '__' ~ salt['test.random_hash']()[-6:] %}
{%-              set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-              set logging_line = '{"TYPE": "INFO", "ACTION": "ORCH - REQUEST APPROVAL - Running requirement state %s (%s) (%s) on %s", "TIMESTAMP": "%s", "ID": "%s"}' %(state,requirement_sls,requirement_state_name,tgt,timestamp,master_id) %}
{{               logging_item(master_logging_file, logging_line)}}
{%               if execute_state %}
requirement_{{ requirement_state_name }}:
  salt.state:
    - tgt: '{{ device_id }}'
    - tgt_type: 'glob'
    - sls: {{ requirement_sls }}
    {#- including pillar if available in the states dictionary #}
    - pillar:
        {%- if 'pillar' in state_payload %}
        state_pillar: {{ state_payload['pillar'] | replace('\\\\','\\') }}
        {%- endif %}
        orch_pillar:
          device: {{ device }}
          version: {{ version }}

{#-              Set device status for requisite checks to data_store #} #}
{{               requirement_state_update_device_status(requirement_state_name=requirement_state_name,state=state,exec_id=globals.get('exec_id', None),update_id=requirements_map['update_content']['ID'],device_id=device_id) }}
{%               else %}
requirement_{{ requirement_state_name }}:
  test.configurable_test_state:
    - changes: False
    - result: False
    - comment: |
        {{ state }} not found under salt://<device>/ nor salt://<utils/ paths
{%               endif %}
{{               logging_salt(type='info', message=">>>> DSF {version}: ORCH - REQUEST APPROVAL - Requirement executed {state} ({sls}) on {tgt}".format(version=dsf_version,state=state,sls=requirement_sls,tgt=tgt),require_state='requirement_'~requirement_state_name) }}
{%-              set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{{               check_state(cap_category=cap_category,device=device,type='requirement',state=requirement_state_name,tgt=tgt,state_sls=requirement_sls,dsf_version=dsf_version,version=version,master_logging_file=master_logging_file,timestamp=timestamp,master_id=master_id,track_progress=False,update_actions_updates_file=False,update_payload=update_payload,device_id=device_id,approval_tgt=approval_tgt,approval_tgt_type=globals.get('approval_tgt_type', 'glob'),update_id=requirements_map['update_content']['ID'],updates_file=requirements_map['updates_file'][approval_tgt_os],exec_id=globals.get('exec_id', None),caller=globals.get('approval_tgt', None),data_store_clean_up=globals.get('requirements_map', {}).get('data_store_clean_up', {})) }}
{%-              set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-              set logging_line = '{"TYPE": "INFO", "ACTION": "ORCH - REQUEST APPROVAL - Requirement executed: %s (%s) (%s) on %s", "TIMESTAMP": "%s", "ID": "%s"}' %(state,requirement_sls,requirement_state_name,tgt,timestamp,master_id) %}
{{               logging_item(master_logging_file, logging_line)}}
{{              nap_time(requirements_map['nap_times']['states_execution']) }}
{%             endfor %}
{%           endfor %}
{#-          No need for nap_time here, only one iteration of tgt is done #}
{%         endfor %}
{%       endif %}
{#-      End of Execute requirements #}
update_device_status_{{ device_id }}_requirements_completed:
  salt.runner:
    - name: dsf_cap.data_add_device_update_status
    - exec_id: {{ globals.get('exec_id', None) }}
    - update_id: {{ requirements_map['update_content']['ID'] }}
    - device_id: '{{ device_id }}'
    - message: 'OK - requirements checks completed'
{%-    endfor %}

{#- At this points requirements check have succeeded or failed, 
in case of failure orchestration will not continue further #}
{%   endif %}
{% endif %}
{#- REF: END CONTROL POINT 1#}



{% if device and version and requirements_map %}
{#-  Update man_dsp_pending_ver on completion #}
{#-  Get tgt #}
{%   for tgt in order_map[device] %}
{%     set tgt_loop = loop %}
{#-    Check what tgt_type based on match pattern #}
{%     set tgt_type = salt['saltutil.runner']('dsf_cap.tgt_type', arg=[tgt]) %}
{%     if tgt_type == 'list' %}
{#-      Removing white spaces #}
{%       set tgt = tgt.replace(" ","") %}
{#-      Resolve and expand list with glob '*' #}
{%       if tgt_type == 'list' and '*' in tgt %}
{%         set tgt = salt['saltutil.runner']('dsf_cap.resolve_glob_list',arg=[tgt]) %}
{%       endif %}
{%     endif %}
{#-    Update man_dsp_pending_ver #}
{%     if requirements_map.get('set_man_dsp_pending_ver', True) %}
{%-      from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros_grains.sls' import man_dsp_pending_ver with context %}
{{       man_dsp_pending_ver(cap_category=cap_category,tgt=tgt,tgt_type=tgt_type,dsf_version=dsf_version,version=version,master_id=master_id,master_logging_file=master_logging_file,caller=globals.get('approval_tgt', None),update_id=requirements_map['update_content']['ID'],logging_filepath=logging_filepath,track_progress=False,update_actions_updates_file=False,exec_id=globals.get('exec_id', None)) }}
{%     endif %}

{%   endfor %}


{#-  Verify devices status and set to available for each device #}
{%-  for _device in update_payload['internal']['devices'].keys() %}
check_device_status_{{ _device }}:
  salt.runner:
    - name: dsf_cap.device_status_check
    - update_id: {{ globals.get('update_id', None) }} 
    - exec_id: {{ globals.get('exec_id', None) }}
    - device_id: {{ _device }}
set_update_avaiable_for_{{ _device }}:
  salt.function:
    - name: dsf_cap.execution_set_status
    - tgt: '{{ globals.get('approval_tgt', None) }}'
    - tgt_type: {{ globals.get('approval_tgt_type', 'glob') }}
    - kwarg:
        status: 'available'
        device_id: {{ _device }}
        update_id: {{ globals.get('update_id', None) }}
        updates_file: {{ globals.get('approver_updates_file', None) }}
        cap_category: {{ cap_category }}
    - require:
      - salt: check_device_status_{{ _device }}
{%-   endfor %}

{#-  Set Update status to available on approval_tgt #}
{%   set update_status = 'available' %}
{{   set_update_status(
        status=update_status,
        device=device,
        device_id=None,
        caller=globals.get('approval_tgt', None),
        tgt_type=globals.get('approval_tgt_type', 'glob'),
        updates_file=globals.get('approver_updates_file', None),
        dsf_version=dsf_version,
        version=version,
        master_id=master_id,
        master_logging_file=globals.get('master_logging_file', None),
        update_id=globals.get('update_id', None),
        logging_filepath=globals.get('logging_filepath', None),
        exec_id=globals.get('exec_id', None),
        update_payload=globals.get('update_payload', None),
        track_progress=False,
        update_actions_updates_file=False,
        cap_category=cap_category,
        requisites={'require': ['salt: check_device_status_*']}
      )
}}
{% do globals.update({'update_status': update_status}) %}


{#   ORCHESTRATION COMPLETED #}
event_ORCH_FINISHED:
  salt.runner:
    - name: event.send
    - tag: DSF_orch/{{ cap_category }}/ORCH_FINISHED
    - data:
        dsf_version: {{ dsf_version | default(None) }}
        dsf_sls: {{ sls.replace('/','.') }}
        device: {{ device | default(None) }}
        version: {{ version | default(None) }}
        master_logging_file: {{ master_logging_file | default(None) }}
        update_id: {{ globals.get('update_id', None) }}
        exec_id: {{ globals.get('exec_id', None) }} 
        exec_status: __slot__:salt:saltutil.runner(dsf_cap.device_status_check,update_id={{ globals.get('update_id', None) }},exec_id={{ globals.get('exec_id', None) }})
        exec_detailed_report: __slot__:salt:saltutil.runner(dsf_cap.device_status_check,update_id={{ globals.get('update_id', None) }},exec_id={{ globals.get('exec_id', None) }},detailed_report=True)
        update_payload: {{ globals.get('update_payload', None) }}
        globals: {{ globals | default(None) }}
ORCHESTRATION_FINISHED:
  test.configurable_test_state:
    - changes: False
    - result: __slot__:salt:saltutil.runner(dsf_cap.device_status_check,update_id={{ globals.get('update_id', None) }},exec_id={{ globals.get('exec_id', None) }})
    - comment: | 
        WORK COMPLETED
        update_id: {{ globals.get('update_id', None) }} 
        exec_id: {{ globals.get('exec_id', None) }}
        update_payload: {{ update_payload | default(None)}}
        globals: {{ globals | default(None) }}
ORCHESTRATION_FINISHED_detailed_report:
  test.configurable_test_state:
    - changes: False
    - result: __slot__:salt:saltutil.runner(dsf_cap.device_status_check,update_id={{ globals.get('update_id', None) }},exec_id={{ globals.get('exec_id', None) }})
    - comment: __slot__:salt:saltutil.runner(dsf_cap.device_status_check,update_id={{ globals.get('update_id', None) }},exec_id={{ globals.get('exec_id', None) }},detailed_report=True)
{{   logging_salt(type='info', message=">>>> DSF {version}: ORCH - REQUEST APPROVAL - Orchestration FINISHED".format(version=dsf_version,),require_state='test: ORCHESTRATION_FINISHED') }}
{%-  set timestamp = None | strftime("%Y-%m-%dT%H:%M:%S.%f") -%}
{%-  set logging_line = '{"TYPE": "INFO", "ACTION": "ORCH - REQUEST APPROVAL - Orchestration FINISHED", "TIMESTAMP": "%s", "ID": "%s"}' %(timestamp, master_id) %}
{{   logging_item(master_logging_file, logging_line)}}
    - require:
      - test: ORCHESTRATION_FINISHED


{#   Clean up data store on_succeeded #}
{%   if globals.get('requirements_map', {}).get('data_store_clean_up', {}).get('on_succeeded', True) %}
clean_up_data_store_{{ globals.get('exec_id', None) }}_on_succeeded:
  salt.runner:
    - name: dsf_cap.data_pop
    - key: {{ globals.get('exec_id', None) }}
    - require:
      - test: ORCHESTRATION_FINISHED
{%   endif %}
{#   Clean up data store on_failed #}
{%   if globals.get('requirements_map', {}).get('data_store_clean_up', {}).get('on_failed', False) %}
clean_up_data_store_{{ globals.get('exec_id', None) }}_on_failed:
  salt.runner:
    - name: dsf_cap.data_pop
    - key: {{ globals.get('exec_id', None) }}
    - require:
      - test: ORCHESTRATION_FINISHED
{%   endif %}

{# OPTIONAL - Automated update execution #}
{%   if salt['slsutil.file_exists']([device, version, device, 'yaml', 'autoexec.yaml'] | join('/')) %}
{%-    from slspath ~ '/' ~ dsf_utils_folder ~ '/dsf_macros_autoexec.sls' import  autoexec_update_execute with context %}
{{     autoexec_update_execute(cap_category=cap_category,dsf_version=dsf_version,version=version,master_id=master_id,master_logging_file=master_logging_file,updates_file=requirements_map['updates_file'],update_id=update_payload['update_content']['ID'],exec_id=globals.get('exec_id', None),update_status=globals.get('update_status', None)) }}
{%   endif %}
{% endif %}