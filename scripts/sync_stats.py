#!/usr/bin/env python3
import subprocess
import xml.etree.ElementTree as ET
import json
from datetime import datetime
import os

VIS_DIR = os.path.dirname(os.path.abspath(__file__)) + '/..'
MACMINI_HOST = '192.168.2.54'
GX10_HOST = '192.168.2.205'
SSH_KEY = os.path.expanduser('~/.ssh/id_ed25519')

def ssh_copy(host, remote_path, local_path):
    cmd = [
        'scp', '-o', 'StrictHostKeyChecking=no',
        '-i', SSH_KEY,
        f'{host}:{remote_path}',
        local_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0

def parse_client_state(xml_file):
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        host_info = root.find('.//host_info')
        hostname = host_info.find('domain_name').text if host_info.find('domain_name') is not None else 'unknown'
        os_name = host_info.find('os_name').text if host_info.find('os_name') is not None else 'unknown'
        os_version = host_info.find('os_version').text if host_info.find('os_version') is not None else ''
        p_model = host_info.find('p_model').text if host_info.find('p_model') is not None else 'unknown'
        m_nbytes = float(host_info.find('m_nbytes').text) if host_info.find('m_nbytes') is not None else 0
        ram_gb = round(m_nbytes / (1024**3), 0)
        
        coprocs = host_info.find('.//coproc_cuda') or host_info.find('.//coproc_apple_gpu')
        gpu_info = 'unknown'
        if coprocs is not None:
            gpu_name = coprocs.find('name')
            if gpu_name is not None:
                gpu_info = gpu_name.text
        
        projects = []
        for project in root.findall('.//project'):
            proj_name = project.find('project_name').text if project.find('project_name') is not None else 'unknown'
            master_url = project.find('master_url').text if project.find('master_url') is not None else ''
            user_name = project.find('user_name').text if project.find('user_name') is not None else 'unknown'
            total_credit = float(project.find('user_total_credit').text) if project.find('user_total_credit') is not None else 0
            rac = float(project.find('user_expavg_credit').text) if project.find('user_expavg_credit') is not None else 0
            user_create = project.find('user_create_time').text if project.find('user_create_time') is not None else ''
            
            projects.append({
                'name': proj_name,
                'url': master_url,
                'user': user_name,
                'total_credit': round(total_credit, 2),
                'rac': round(rac, 2),
                'joined': datetime.fromtimestamp(float(user_create)).strftime('%Y-%m-%d') if user_create else 'unknown'
            })
        
        return {
            'name': hostname.split('-')[0].title() if '-' in hostname else hostname,
            'hostname': hostname,
            'os': f"{os_name} {os_version}".strip(),
            'cpu': p_model[:50],
            'ram_gb': int(ram_gb),
            'projects': projects
        }
    except Exception as e:
        print(f"Error parsing {xml_file}: {e}")
        return None

def main():
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Starting BOINC stats sync...")
    
    # Sync Mac mini
    print(f"Fetching Mac mini stats from {MACMINI_HOST}...")
    macmini_path = os.path.join(VIS_DIR, 'client_state_macmini.xml')
    if ssh_copy(MACMINI_HOST, '/Library/Application Support/BOINC Data/client_state.xml', macmini_path):
        print("Mac mini synced successfully")
    else:
        print("Warning: Failed to sync Mac mini")
    
    # Sync GX10
    print(f"Fetching GX10 stats from {GX10_HOST}...")
    gx10_path = os.path.join(VIS_DIR, 'client_state_gx10.xml')
    if ssh_copy(GX10_HOST, '/Users/raffael/Projekte/Visualization/client_state.xml', gx10_path):
        print("GX10 synced successfully")
    else:
        print("Warning: Failed to sync GX10")
    
    # Parse and update stats.json
    mac_mini = parse_client_state(macmini_path)
    gx10 = parse_client_state(gx10_path)
    
    machines = [m for m in [mac_mini, gx10] if m]
    
    combined_credit = sum(p['total_credit'] for m in machines for p in m['projects'])
    combined_rac = sum(p['rac'] for m in machines for p in m['projects'])
    einstein_total = sum(p['total_credit'] for m in machines for p in m['projects'] if 'einstein' in p['name'].lower())
    einstein_rac = sum(p['rac'] for m in machines for p in m['projects'] if 'einstein' in p['name'].lower())
    milkyway_total = sum(p['total_credit'] for m in machines for p in m['projects'] if 'milkyway' in p['name'].lower())
    milkyway_rac = sum(p['rac'] for m in machines for p in m['projects'] if 'milkyway' in p['name'].lower())
    
    result = {
        'last_updated': datetime.utcnow().isoformat() + 'Z',
        'machines': machines,
        'combined': {
            'total_credit': round(combined_credit, 2),
            'total_rac': round(combined_rac, 2),
            'einstein': {'total': round(einstein_total, 2), 'rac': round(einstein_rac, 2)},
            'milkyway': {'total': round(milkyway_total, 2), 'rac': round(milkyway_rac, 2)}
        }
    }
    
    stats_path = os.path.join(VIS_DIR, 'stats.json')
    with open(stats_path, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Stats updated: {combined_credit:.0f} total credits, {combined_rac:.0f} RAC")

if __name__ == '__main__':
    main()
