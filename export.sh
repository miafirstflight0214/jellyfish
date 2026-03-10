#!/bin/bash
# Export OpenClaw agent data to JSON for Jellyfish dashboard
# Usage: ./export.sh [output_dir]

OUT_DIR="${1:-.}"
AGENTS_DIR="$HOME/.openclaw/agents"
OUTPUT="$OUT_DIR/data/agents.json"

mkdir -p "$OUT_DIR/data"

echo '{' > "$OUTPUT"
echo '  "exported": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",' >> "$OUTPUT"
echo '  "agents": [' >> "$OUTPUT"

first=true
for agent_dir in "$AGENTS_DIR"/*/; do
    agent=$(basename "$agent_dir")
    [ "$agent" = "gemini-image" ] && continue

    # main agent: workspace files are in ~/.openclaw/workspace/, not agents/main/
    workspace_dir="$agent_dir"
    if [ "$agent" = "main" ]; then
        workspace_dir="$HOME/.openclaw/workspace/"
    fi

    $first || echo '    ,' >> "$OUTPUT"
    first=false

    # Identity
    name="$agent"
    emoji=""
    role=""
    vibe=""
    tagline=""

    if [ -f "$workspace_dir/IDENTITY.md" ]; then
        name=$(grep -m1 '^\- \*\*Name' "$workspace_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        emoji=$(grep -m1 '^\- \*\*Emoji' "$workspace_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        role=$(grep -m1 '^\- \*\*Role' "$workspace_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        vibe=$(grep -m1 '^\- \*\*Vibe' "$workspace_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        tagline=$(grep -m1 '^_' "$workspace_dir/IDENTITY.md" | sed 's/^_//;s/_$//' | tr -d '\r')
    fi

    # Soul - first line of "我是谁" section
    soul_intro=""
    soul_intro_en=""
    if [ -f "$workspace_dir/SOUL.md" ]; then
        soul_intro=$(awk '/^## 我是谁/{getline; if($0!="") print; exit}' "$workspace_dir/SOUL.md" | tr -d '\r')
    fi
    # English intro mappings
    case "$agent" in
        main) soul_intro_en="The central hub. Coordinates Nemo and Nova, manages shared knowledge." ;;
        nemo) soul_intro_en="Life assistant. Handles daily affairs, finds food and fun for May." ;;
        nova) soul_intro_en="Code partner. Writes code alongside Mia, helps May ship projects." ;;
    esac

    # Memory stats
    memory_file="$workspace_dir/MEMORY.md"
    memory_lines=0
    memory_updated=""
    if [ -f "$memory_file" ]; then
        memory_lines=$(wc -l < "$memory_file" | tr -d ' ')
        memory_updated=$(stat -f %Sm -t %Y-%m-%dT%H:%M:%S "$memory_file" 2>/dev/null || stat -c %y "$memory_file" 2>/dev/null | cut -d. -f1)
    fi

    # Daily logs
    daily_logs="[]"
    if [ -d "$workspace_dir/memory" ]; then
        daily_logs="["
        dl_first=true
        for log in "$workspace_dir"/memory/2026-*.md; do
            [ -f "$log" ] || continue
            $dl_first || daily_logs="$daily_logs,"
            dl_first=false
            log_name=$(basename "$log" .md)
            log_lines=$(wc -l < "$log" | tr -d ' ')
            daily_logs="$daily_logs{\"date\":\"$log_name\",\"lines\":$log_lines}"
        done
        daily_logs="$daily_logs]"
    fi

    # Other memory files
    other_memory="[]"
    if [ -d "$workspace_dir/memory" ]; then
        other_memory="["
        om_first=true
        for mf in "$workspace_dir"/memory/*.md; do
            [ -f "$mf" ] || continue
            mf_name=$(basename "$mf")
            echo "$mf_name" | grep -q '^2026-' && continue
            $om_first || other_memory="$other_memory,"
            om_first=false
            mf_lines=$(wc -l < "$mf" | tr -d ' ')
            other_memory="$other_memory{\"name\":\"$mf_name\",\"lines\":$mf_lines}"
        done
        other_memory="$other_memory]"
    fi

    # Session count
    session_count=0
    if [ -d "$agent_dir/sessions" ]; then
        session_count=$(ls "$agent_dir"/sessions/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Config files with line counts
    config_files="["
    cf_first=true
    for cf_name in SOUL.md IDENTITY.md MEMORY.md USER.md HEARTBEAT.md TOOLS.md AGENTS.md; do
        $cf_first || config_files="$config_files,"
        cf_first=false
        cf_path="$workspace_dir/$cf_name"
        if [ -f "$cf_path" ]; then
            cf_lines=$(wc -l < "$cf_path" | tr -d ' ')
            config_files="$config_files{\"name\":\"$cf_name\",\"exists\":true,\"lines\":$cf_lines}"
        else
            config_files="$config_files{\"name\":\"$cf_name\",\"exists\":false,\"lines\":0}"
        fi
    done
    config_files="$config_files]"

    # Backward compat booleans
    has_soul=$([ -f "$workspace_dir/SOUL.md" ] && echo true || echo false)
    has_identity=$([ -f "$workspace_dir/IDENTITY.md" ] && echo true || echo false)
    has_memory=$([ -f "$workspace_dir/MEMORY.md" ] && echo true || echo false)
    has_user=$([ -f "$workspace_dir/USER.md" ] && echo true || echo false)
    has_heartbeat=$([ -f "$workspace_dir/HEARTBEAT.md" ] && echo true || echo false)
    has_tools=$([ -f "$workspace_dir/TOOLS.md" ] && echo true || echo false)
    has_agents=$([ -f "$workspace_dir/AGENTS.md" ] && echo true || echo false)

    # MEMORY.md sections
    memory_sections="[]"
    if [ -f "$memory_file" ]; then
        memory_sections="["
        ms_first=true
        while IFS= read -r line; do
            $ms_first || memory_sections="$memory_sections,"
            ms_first=false
            section=$(echo "$line" | sed 's/^## //' | tr -d '\r')
            memory_sections="$memory_sections\"$section\""
        done < <(grep '^## ' "$memory_file")
        memory_sections="$memory_sections]"
    fi

    # English tagline mappings
    tagline_en=""
    case "$agent" in
        main) tagline_en="This isn't just metadata. It's the start of figuring out who I am." ;;
        nemo) tagline_en="Come to me for food, fun, and daily life." ;;
        nova) tagline_en="When I'm here, problems get solved." ;;
    esac

    # Heartbeat interval (from openclaw status)
    heartbeat_interval=""
    case "$agent" in
        main) heartbeat_interval="disabled" ;;
        nemo) heartbeat_interval="1h" ;;
        nova) heartbeat_interval="2h" ;;
        *) heartbeat_interval="—" ;;
    esac

    # Heartbeat content (extract tasks — ### headers or top-level bullets)
    heartbeat_tasks="[]"
    if [ -f "$workspace_dir/HEARTBEAT.md" ]; then
        heartbeat_tasks="["
        hb_first=true
        while IFS= read -r line; do
            task=$(echo "$line" | sed 's/^### [0-9]*\. *//;s/^- //' | tr -d '\r' | sed 's/"/\\"/g')
            [ -z "$task" ] && continue
            $hb_first || heartbeat_tasks="$heartbeat_tasks,"
            hb_first=false
            heartbeat_tasks="$heartbeat_tasks\"$task\""
        done < <(grep -E '^### |^- ' "$workspace_dir/HEARTBEAT.md" | grep -v '^- \[' | head -10)
        heartbeat_tasks="$heartbeat_tasks]"
    fi

    cat >> "$OUTPUT" << EOF
    {
      "id": "$agent",
      "name": "$name",
      "emoji": "$emoji",
      "role": "$role",
      "vibe": "$vibe",
      "tagline": "$tagline",
      "taglineEn": "$tagline_en",
      "soulIntro": "$soul_intro",
      "soulIntroEn": "$soul_intro_en",
      "config": {
        "soul": $has_soul,
        "identity": $has_identity,
        "memory": $has_memory,
        "user": $has_user,
        "heartbeat": $has_heartbeat,
        "tools": $has_tools,
        "agents": $has_agents
      },
      "configFiles": $config_files,
      "memory": {
        "longTermLines": $memory_lines,
        "lastUpdated": "$memory_updated",
        "sections": $memory_sections,
        "dailyLogs": $daily_logs,
        "otherFiles": $other_memory
      },
      "sessions": $session_count,
      "heartbeatInterval": "$heartbeat_interval",
      "heartbeatTasks": $heartbeat_tasks
    }
EOF
done

echo '  ],' >> "$OUTPUT"

# Cron jobs
echo '  "crons": ' >> "$OUTPUT"
openclaw cron list --json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
jobs = data.get('jobs', data if isinstance(data, list) else [])
out = []
def detect_outputs(msg, delivery):
    tags = []
    if any(k in msg for k in ['memory/', 'MEMORY', 'learnings.md', '保存到', '追加到', '写入']): tags.append('file')
    if 'nano-banana' in msg: tags.append('art')
    ch = delivery.get('channel','')
    if ch: tags.append(ch)
    if not tags: tags.append('discord')
    return tags
for j in jobs:
    sched = j.get('schedule', {})
    state = j.get('state', {})
    payload = j.get('payload', {})
    msg = payload.get('message', '')
    delivery = j.get('delivery', {})
    outputs = detect_outputs(msg, delivery)
    # Truncate task message to first 100 chars
    if len(msg) > 100: msg = msg[:100] + '...'
    out.append({
        'id': j.get('id',''),
        'name': j.get('name',''),
        'schedule': sched.get('expr',''),
        'tz': sched.get('tz',''),
        'agent': j.get('agentId',''),
        'status': state.get('lastStatus','idle'),
        'enabled': j.get('enabled', True),
        'lastRun': state.get('lastRunAtMs'),
        'task': msg,
        'deliveryChannel': delivery.get('channel',''),
        'deliveryTo': delivery.get('to',''),
        'outputs': outputs,
    })
print(json.dumps(out, ensure_ascii=False, indent=2))
" >> "$OUTPUT" 2>/dev/null

# Shared knowledge files
echo '  ,"shared": [' >> "$OUTPUT"
shared_first=true
for sf in "$HOME/.openclaw/shared/art-study"/**/*.md "$HOME/.openclaw/shared/art-study"/*.md; do
    [ -f "$sf" ] || continue
    $shared_first || echo '    ,' >> "$OUTPUT"
    shared_first=false
    sf_name=$(echo "$sf" | sed "s|$HOME/.openclaw/shared/art-study/||")
    sf_lines=$(wc -l < "$sf" | tr -d ' ')
    echo "    {\"name\":\"$sf_name\",\"lines\":$sf_lines}" >> "$OUTPUT"
done
echo '  ]' >> "$OUTPUT"

echo '}' >> "$OUTPUT"

echo "Exported to $OUTPUT"
