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

    $first || echo '    ,' >> "$OUTPUT"
    first=false

    # Identity
    name="$agent"
    emoji=""
    role=""
    vibe=""
    tagline=""

    if [ -f "$agent_dir/IDENTITY.md" ]; then
        name=$(grep -m1 '^\- \*\*Name' "$agent_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        emoji=$(grep -m1 '^\- \*\*Emoji' "$agent_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        role=$(grep -m1 '^\- \*\*Role' "$agent_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        vibe=$(grep -m1 '^\- \*\*Vibe' "$agent_dir/IDENTITY.md" | sed 's/.*\*\* *//' | tr -d '\r')
        tagline=$(grep -m1 '^_' "$agent_dir/IDENTITY.md" | sed 's/^_//;s/_$//' | tr -d '\r')
    fi

    # Soul - first line of "我是谁" section
    soul_intro=""
    if [ -f "$agent_dir/SOUL.md" ]; then
        soul_intro=$(awk '/^## 我是谁/{getline; if($0!="") print; exit}' "$agent_dir/SOUL.md" | tr -d '\r')
    fi

    # Memory stats
    memory_file="$agent_dir/MEMORY.md"
    memory_lines=0
    memory_updated=""
    if [ -f "$memory_file" ]; then
        memory_lines=$(wc -l < "$memory_file" | tr -d ' ')
        memory_updated=$(stat -f %Sm -t %Y-%m-%dT%H:%M:%S "$memory_file" 2>/dev/null || stat -c %y "$memory_file" 2>/dev/null | cut -d. -f1)
    fi

    # Daily logs
    daily_logs="[]"
    if [ -d "$agent_dir/memory" ]; then
        daily_logs="["
        dl_first=true
        for log in "$agent_dir"/memory/2026-*.md; do
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
    if [ -d "$agent_dir/memory" ]; then
        other_memory="["
        om_first=true
        for mf in "$agent_dir"/memory/*.md; do
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

    # Config files present
    has_soul=$([ -f "$agent_dir/SOUL.md" ] && echo true || echo false)
    has_identity=$([ -f "$agent_dir/IDENTITY.md" ] && echo true || echo false)
    has_memory=$([ -f "$agent_dir/MEMORY.md" ] && echo true || echo false)
    has_user=$([ -f "$agent_dir/USER.md" ] && echo true || echo false)
    has_heartbeat=$([ -f "$agent_dir/HEARTBEAT.md" ] && echo true || echo false)
    has_tools=$([ -f "$agent_dir/TOOLS.md" ] && echo true || echo false)
    has_agents=$([ -f "$agent_dir/AGENTS.md" ] && echo true || echo false)

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

    cat >> "$OUTPUT" << EOF
    {
      "id": "$agent",
      "name": "$name",
      "emoji": "$emoji",
      "role": "$role",
      "vibe": "$vibe",
      "tagline": "$tagline",
      "soulIntro": "$soul_intro",
      "config": {
        "soul": $has_soul,
        "identity": $has_identity,
        "memory": $has_memory,
        "user": $has_user,
        "heartbeat": $has_heartbeat,
        "tools": $has_tools,
        "agents": $has_agents
      },
      "memory": {
        "longTermLines": $memory_lines,
        "lastUpdated": "$memory_updated",
        "sections": $memory_sections,
        "dailyLogs": $daily_logs,
        "otherFiles": $other_memory
      },
      "sessions": $session_count
    }
EOF
done

echo '  ]' >> "$OUTPUT"
echo '}' >> "$OUTPUT"

echo "Exported to $OUTPUT"
