#!/bin/bash
# Sync BOINC stats from Mac mini and GX10

VIS_DIR=/Users/raffael/Projekte/Visualization
LOG_FILE=/Users/raffael/Projekte/Visualization/sync.log

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting BOINC stats sync"

# Mac mini BOINC data
MACMINI_BOINC="/Library/Application Support/BOINC Data/client_state.xml"
MACMINI_HOST="192.168.2.54"
SSH_KEY="/Users/raffael/.ssh/id_ed25519"

# GX10 BOINC data (via SSH)
GX10_HOST="192.168.2.205"
GX10_USER="raffael"

# Sync Mac mini stats
log "Fetching Mac mini stats..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$MACMINI_HOST:$MACMINI_BOINC" "$VIS_DIR/client_state_macmini_new.xml" 2>> "$LOG_FILE"
if [ $? -eq 0 ]; then
    mv "$VIS_DIR/client_state_macmini_new.xml" "$VIS_DIR/client_state_macmini.xml"
    log "Mac mini stats synced successfully"
else
    log "ERROR: Failed to sync Mac mini stats"
fi

# Sync GX10 stats
log "Fetching GX10 stats..."
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$GX10_USER@$GX10_HOST:/home/raffael/Projekte/Visualization/client_state.xml" "$VIS_DIR/client_state_gx10_new.xml" 2>> "$LOG_FILE"
if [ $? -eq 0 ]; then
    mv "$VIS_DIR/client_state_gx10_new.xml" "$VIS_DIR/client_state_gx10.xml"
    log "GX10 stats synced successfully"
else
    log "ERROR: Failed to sync GX10 stats"
fi

# Extract and update stats.json
log "Updating stats.json..."
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
from datetime import datetime

def parse_client_state(xml_file, machine_name):
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        # Get host info
        host_info = root.find('.//host_info')
        hostname = host_info.find('domain_name').text if host_info.find('domain_name') is not None else 'unknown'
        os_name = host_info.find('os_name').text if host_info.find('os_name') is not None else 'unknown'
        os_version = host_info.find('os_version').text if host_info.find('os_version') is not None else ''
        p_model = host_info.find('p_model').text if host_info.find('p_model') is not None else 'unknown'
        m_nbytes = float(host_info.find('m_nbytes').text) if host_info.find('m_nbytes') is not None else 0
        ram_gb = round(m_nbytes / (1024**3), 0)
        
        # Get GPU info
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
            'name': machine_name,
            'hostname': hostname,
            'os': f"{os_name} {os_version}".strip(),
            'cpu': p_model[:50],
            'ram_gb': int(ram_gb),
            'projects': projects
        }
    except Exception as e:
        print(f"Error parsing {xml_file}: {e}")
        return None

# Parse both machines
mac_mini = parse_client_state('/Users/raffael/Projekte/Visualization/client_state_macmini.xml', 'Mac mini')
gx10 = parse_client_state('/Users/raffael/Projekte/Visualization/client_state_gx10.xml', 'GX10')

# Calculate combined stats
combined_credit = 0
combined_rac = 0
einstein_total = 0
einstein_rac = 0
milkyway_total = 0
milkyway_rac = 0

machines = []
for m in [mac_mini, gx10]:
    if m:
        machines.append(m)
        for p in m['projects']:
            combined_credit += p['total_credit']
            combined_rac += p['rac']
            if 'einstein' in p['name'].lower():
                einstein_total += p['total_credit']
                einstein_rac += p['rac']
            elif 'milkyway' in p['name'].lower():
                milkyway_total += p['total_credit']
                milkyway_rac += p['rac']

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

with open('/Users/raffael/Projekte/Visualization/stats.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Stats updated: {combined_credit:.0f} total credits, {combined_rac:.0f} RAC")
PYEOF

log "Stats update complete"
