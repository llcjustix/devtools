#!/bin/bash

echo "=========================================="
echo "Testing Jitsi → Meeting-Service Webhooks"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Check meeting-service is running
echo -e "${YELLOW}[1/5] Checking meeting-service...${NC}"
if curl -s http://localhost:2031/actuator/health | grep -q "UP"; then
    echo -e "${GREEN}✓ Meeting-service is UP${NC}"
else
    echo -e "${RED}✗ Meeting-service is DOWN${NC}"
    echo "Please start meeting-service first:"
    echo "  cd ~/IdeaProjects/meeting-service"
    echo "  ./mvnw spring-boot:run"
    exit 1
fi
echo ""

# Step 2: Check Prosody modules
echo -e "${YELLOW}[2/5] Checking Prosody modules...${NC}"
PROSODY_LOGS=$(docker logs jitsi-prosody 2>&1)

if echo "$PROSODY_LOGS" | grep -q "jitsi_webhooks_enhanced.*loaded"; then
    echo -e "${GREEN}✓ jitsi_webhooks_enhanced loaded${NC}"
else
    echo -e "${RED}✗ jitsi_webhooks_enhanced NOT loaded${NC}"
fi

if echo "$PROSODY_LOGS" | grep -q "room_access_validator.*loaded"; then
    echo -e "${GREEN}✓ room_access_validator loaded${NC}"
else
    echo -e "${RED}✗ room_access_validator NOT loaded${NC}"
fi

if echo "$PROSODY_LOGS" | grep -q "host.docker.internal:2031"; then
    echo -e "${GREEN}✓ Using correct URL (host.docker.internal:2031)${NC}"
else
    echo -e "${RED}✗ Wrong URL in Prosody${NC}"
fi
echo ""

# Step 3: Test connectivity from Prosody to meeting-service
echo -e "${YELLOW}[3/5] Testing connectivity from Prosody...${NC}"
if docker exec jitsi-prosody wget -qO- http://host.docker.internal:2031/actuator/health 2>&1 | grep -q "UP"; then
    echo -e "${GREEN}✓ Prosody can reach meeting-service${NC}"
else
    echo -e "${RED}✗ Prosody CANNOT reach meeting-service${NC}"
    echo "Network issue detected!"
    exit 1
fi
echo ""

# Step 4: Create a test meeting
echo -e "${YELLOW}[4/5] Creating test meeting...${NC}"

# You'll need to get a valid JWT token first
# For now, let's try without authentication (if it's disabled)
MEETING_RESPONSE=$(curl -s -X POST http://localhost:2031/meetings \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Webhook Test Meeting",
    "description": "Testing webhooks",
    "meetingType": "GROUP",
    "isPublic": true,
    "durationMinutes": 60
  }' 2>&1)

# Check if we got a 401 (authentication required)
if echo "$MEETING_RESPONSE" | grep -q "401"; then
    echo -e "${YELLOW}⚠ Authentication required. Please provide JWT token.${NC}"
    echo ""
    echo "To test manually:"
    echo "1. Get JWT token from your auth service"
    echo "2. Create meeting:"
    echo '   curl -X POST http://localhost:2031/meetings \'
    echo '     -H "Authorization: Bearer YOUR_TOKEN" \'
    echo '     -H "Content-Type: application/json" \'
    echo '     -d '"'"'{"title":"Test","meetingType":"GROUP","isPublic":true,"durationMinutes":60}'"'"
    echo "3. Copy the roomName from response"
    echo "4. Open http://localhost:8001/ROOM_NAME in browser"
    echo "5. Watch meeting-service logs for webhook calls"
    exit 0
fi

ROOM_NAME=$(echo "$MEETING_RESPONSE" | grep -o '"roomName":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ROOM_NAME" ]; then
    echo -e "${RED}✗ Failed to create meeting${NC}"
    echo "Response: $MEETING_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Meeting created: $ROOM_NAME${NC}"
echo ""

# Step 5: Instructions for testing
echo -e "${YELLOW}[5/5] Next steps to test webhooks:${NC}"
echo ""
echo "1. In a new terminal, watch meeting-service logs:"
echo -e "   ${GREEN}tail -f logs/meeting-service.log${NC}"
echo "   Or if running from IDE, check console output"
echo ""
echo "2. Open Jitsi meeting in browser:"
echo -e "   ${GREEN}http://localhost:8001/$ROOM_NAME${NC}"
echo ""
echo "3. You should see these webhooks in meeting-service logs:"
echo "   - Room created: roomName=$ROOM_NAME"
echo "   - Validate access: roomName=$ROOM_NAME"
echo "   - Room validation succeeded"
echo "   - User joined: roomName=$ROOM_NAME"
echo ""
echo "4. Watch Prosody logs in another terminal:"
echo -e "   ${GREEN}docker logs -f jitsi-prosody 2>&1 | grep -E '(webhook|validate|room)'${NC}"
echo ""
echo "=========================================="
echo "Test setup complete!"
echo "=========================================="
