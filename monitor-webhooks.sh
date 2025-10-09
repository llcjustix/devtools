#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=========================================="
echo "Monitoring Webhooks (Ctrl+C to stop)"
echo -e "==========================================${NC}"
echo ""
echo -e "${BLUE}Watching for webhook activity...${NC}"
echo ""

# Function to monitor Prosody logs
monitor_prosody() {
    docker logs -f jitsi-prosody 2>&1 | while read line; do
        if echo "$line" | grep -qE "(webhook|Webhook|validate|Validate|Room created|User joined|User left)"; then
            echo -e "${BLUE}[PROSODY]${NC} $line"
        fi
    done
}

# Function to check meeting-service logs
check_meeting_service() {
    # Try different log locations
    if [ -f "/Users/nasibullohyandashev/IdeaProjects/meeting-service/logs/meeting-service.log" ]; then
        tail -f "/Users/nasibullohyandashev/IdeaProjects/meeting-service/logs/meeting-service.log" | while read line; do
            if echo "$line" | grep -qiE "(webhook|room.*created|validate.*access|user.*joined|user.*left)"; then
                echo -e "${GREEN}[MEETING-SERVICE]${NC} $line"
            fi
        done
    else
        echo -e "${YELLOW}Note: Meeting-service log file not found. If running from IDE, check console output.${NC}"
        echo ""
    fi
}

# Monitor both in parallel
monitor_prosody &
PROSODY_PID=$!

check_meeting_service &
MEETING_PID=$!

# Trap Ctrl+C to clean up
trap "echo ''; echo 'Stopping monitors...'; kill $PROSODY_PID $MEETING_PID 2>/dev/null; exit 0" INT

# Wait
wait
