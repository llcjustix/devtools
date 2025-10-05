# Prosody Complete Webhook Module ⭐ RECOMMENDED

**Module:** `mod_jitsi_webhooks.lua`
**Type:** Complete meeting lifecycle tracking
**Recommendation:** Use this for production deployments

## Quick Links

- **[Basic Module](../prosody-plugin/README.md)** - Simpler alternative without participant tracking
- **[Jitsi UI Plugin](../jitsi-plugin/README.md)** - Frontend configuration
- **[Main Documentation](../README.md)** - Service architecture and API

---

## Table of Contents

- [Features vs Basic Module](#features-vs-basic-module)
- [Installation](#installation)
- [Webhook Endpoints](#webhook-endpoints)
- [Duration Enforcement](#duration-enforcement)
- [Private Meeting Authentication](#private-meeting-authentication)
- [Configuration Options](#configuration-options)
- [Jibri Recording Integration](#jibri-recording-integration)
- [Debugging](#debugging)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

---

## Features vs Basic Module

| Feature | Basic Module | This Module |
|---------|--------------|-------------|
| Room configuration | ✅ | ✅ |
| Access validation | ✅ | ✅ |
| Participant tracking | ❌ | ✅ |
| Duration enforcement | ❌ | ✅ (Prosody timer) |
| Meeting lifecycle | ❌ | ✅ (SCHEDULED→IN_PROGRESS→COMPLETED) |
| OAuth authentication | ❌ | ✅ (Private meetings) |
| Moderator tracking | ❌ | ✅ |
| Jibri recording | ⚠️ Basic | ✅ Full integration |

---

## Installation

See **[Main README - Prosody Module Installation](../README.md#-prosody-module-installation)** for step-by-step setup instructions.

**Quick reference:**

### 1. Copy Module

```bash
sudo cp mod_jitsi_webhooks.lua /usr/share/jitsi-meet/prosody-plugins/
sudo chown root:root /usr/share/jitsi-meet/prosody-plugins/mod_jitsi_webhooks.lua
sudo chmod 644 /usr/share/jitsi-meet/prosody-plugins/mod_jitsi_webhooks.lua
```

### 2. Configure Prosody

Edit `/etc/prosody/conf.d/meet.yourdomain.com.cfg.lua`:

```lua
Component "conference.meet.yourdomain.com" "muc"
    modules_enabled = {
        "muc_meeting_id";
        "muc_domain_mapper";
        "jitsi_webhooks";  -- Add this
    }

    -- Webhook configuration
    jitsi_webhook_url = "https://api.yourdomain.com/webhooks/jitsi"
    jitsi_webhook_secret = "your-secret-key-here"
    jitsi_webhook_timeout = 5
    jitsi_file_service_url = "http://file-service:2027"  -- For Jibri uploads
```

**For private meetings with OAuth:**

```lua
VirtualHost "meet.yourdomain.com"
    authentication = "token"  -- Enable JWT validation
    app_id = "your-app-id"
    app_secret = "your-keycloak-secret"
    allow_empty_token = true  -- Allow public meetings without JWT
```

### 3. Configure Backend

Set webhook secret in `application.yml`:

```yaml
jitsi:
  webhook:
    secret: your-secret-key-here  # Must match Prosody config
```

Or via environment variable:

```bash
export JITSI_WEBHOOK_SECRET="your-secret-key-here"
```

### 4. Restart Services

```bash
sudo systemctl restart prosody
sudo systemctl restart jicofo
sudo systemctl restart jitsi-videobridge2
```

---

## Webhook Endpoints

This module implements **7 webhook endpoints**:

### 1. Room Created

**Called:** When Prosody creates a new MUC room

```
POST /webhooks/jitsi/room-created
{
  "roomName": "abc-defg-hij",
  "roomJid": "abc-defg-hij@conference.domain",
  "timestamp": 1234567890
}
```

**Backend returns:**
- Room configuration (moderators, settings, maxDurationMinutes)
- Module stores meetingId, schedules duration timer, applies config

### 2. Validate Access

**Called:** Before each user joins

```
POST /webhooks/jitsi/validate-access
{
  "meetingId": 123,
  "roomName": "abc-defg-hij",
  "userJid": "user@domain.com",
  "userName": "John Doe",
  "bearerToken": "eyJhbGc...",  -- JWT (null for public)
  "timestamp": 1234567890
}
```

**Backend validates:**
- Meeting status (not cancelled/completed/expired)
- For private meetings: validates JWT and checks invitations

### 3. User Joined

**Called:** When user successfully joins

```
POST /webhooks/jitsi/user-joined
{
  "roomName": "abc-defg-hij",
  "userJid": "user@domain.com",
  "userName": "John Doe",
  "isModerator": true,
  "timestamp": 1234567890
}
```

**Backend actions:**
- Creates participant record with joinedAt timestamp
- Updates meeting status to IN_PROGRESS (if first user)

### 4. User Left

**Called:** When user leaves

```
POST /webhooks/jitsi/user-left
{
  "roomName": "abc-defg-hij",
  "userJid": "user@domain.com",
  "userName": "John Doe",
  "timestamp": 1234567890
}
```

**Backend actions:**
- Updates participant leftAt timestamp
- Calculates duration (leftAt - joinedAt)

### 5. Room Destroyed

**Called:** When all users leave

```
POST /webhooks/jitsi/room-destroyed
{
  "roomName": "abc-defg-hij",
  "roomJid": "abc-defg-hij@conference.domain",
  "reason": "all_users_left",
  "timestamp": 1234567890
}
```

**Backend actions:**
- Updates meeting status to COMPLETED
- Sets endedAt timestamp

### 6. Moderator Changed

**Called:** When moderator status changes

```
POST /webhooks/jitsi/moderator-changed
{
  "roomName": "abc-defg-hij",
  "userJid": "user@domain.com",
  "userName": "John Doe",
  "isModerator": true,
  "changedBy": "admin@domain.com",
  "timestamp": 1234567890
}
```

**Backend actions:**
- Updates participant moderator flag
- Tracks role changes for audit

### 7. Recording Events

See [Jibri Recording Integration](#jibri-recording-integration) section below.

---

## Duration Enforcement

**Automatic room destruction after duration expires:**

### How It Works

1. **Backend returns maxDurationMinutes** in `/room-created` response:
   ```json
   {
     "maxDurationMinutes": 60,
     ...
   }
   ```

2. **Module schedules Prosody timer:**
   ```lua
   local duration_seconds = maxDurationMinutes * 60
   module:add_timer(duration_seconds, function()
       module:log("warn", "Duration limit reached, destroying room...")
       room:destroy(nil, "Meeting duration limit has been reached")
       return false  -- Don't repeat
   end)
   ```

3. **Timer expires:**
   - All users kicked with message "Duration limit reached"
   - Prosody calls `/room-destroyed` webhook
   - Backend marks meeting as COMPLETED

### Additional Enforcement

Backend also blocks new joins in `/validate-access`:

```java
if (meeting.expiresAt != null && now.isAfter(expiresAt)) {
    return DENY("Meeting duration has expired");
}
```

This prevents users from joining after duration expires, even if room still exists.

---

## Private Meeting Authentication

**OAuth JWT Flow:**

### How It Works

1. **User gets OAuth token** from Keycloak (already logged in)

2. **Frontend constructs URL:**
   ```
   https://meet.domain.com/abc-defg-hij?jwt={user_oauth_token}
   ```

3. **Prosody validates JWT signature** (mod_token_verification checks Keycloak secret)

4. **Module extracts token from session:**
   ```lua
   local bearer_token = session.auth_token or session.jitsi_meet_context_user
   ```

5. **Module calls `/validate-access` with token:**
   ```lua
   {
     "bearerToken": "eyJhbGc...",
     ...
   }
   ```

6. **Backend validates:**
   ```java
   Jwt jwt = jwtDecoder.decode(bearerToken);  // Validates Keycloak signature
   Long userId = SecurityUtils.extractUserIdFromJwt(jwt);
   boolean isInvited = meeting.getInvitations().stream()
       .anyMatch(inv -> userId.equals(inv.getUserId()));

   if (!isInvited) {
       return DENY("You are not invited to this meeting");
   }
   ```

### Room Access Configuration

Module automatically configures room based on `isPublic` flag:

```lua
if config.isPublic == false then
    room:set_members_only(true)  -- Private meeting
else
    room:set_members_only(false)  -- Public meeting
end
```

---

## Configuration Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `jitsi_webhook_url` | ✅ | - | Backend webhook base URL |
| `jitsi_webhook_secret` | ⚠️ Production | "" | Shared secret for authentication |
| `jitsi_webhook_timeout` | ❌ | 5 | HTTP timeout (seconds) |
| `jitsi_file_service_url` | ⚠️ Jibri only | - | File-service URL for recording uploads |

**Security Warning:** Always set `jitsi_webhook_secret` in production! Empty secret accepts all requests (insecure).

---

## Jibri Recording Integration

### Architecture

```
Jitsi Meet → Jibri → File-Service (MinIO) → Meeting-Service
                 ↓
          Meeting-Service (webhooks)
```

### File Upload Flow

#### 1. Recording Session Structure

Each recording session creates files in MinIO:

```
/roomName/sessionId/
├── video.mp4           # Main recording
├── chat.json           # Chat messages (if enabled)
└── whiteboard.json     # Whiteboard data (if enabled)
```

- **roomName**: Meeting room identifier (e.g., `abc-defg-hij`)
- **sessionId**: Unique recording session ID (timestamp-based)
- **referenceId**: Meeting ID from database (for queries)

#### 2. Jibri Finalize Script

Create `/usr/local/bin/jibri-finalize.sh`:

```bash
#!/bin/bash
# Jibri finalize script - uploads recording artifacts to file-service
# Called by Jibri after recording stops

set -e

# Arguments from Jibri
RECORDING_DIR="$1"          # /tmp/recordings/rec-abc123
ROOM_NAME="$2"              # abc-defg-hij
SESSION_ID="$3"             # 20250105-143022-abc123

# Configuration (from environment or hardcoded)
FILE_SERVICE_URL="${FILE_SERVICE_URL:-http://file-service:2027}"
MEETING_SERVICE_URL="${MEETING_SERVICE_URL:-http://meeting-service:2031}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"

echo "=== Jibri Finalize Script Started ==="
echo "Recording Dir: $RECORDING_DIR"
echo "Room Name: $ROOM_NAME"
echo "Session ID: $SESSION_ID"

# Get meetingId from meeting-service by roomName
MEETING_ID=$(curl -s "${MEETING_SERVICE_URL}/api/meetings/room/${ROOM_NAME}" | jq -r '.id')

if [ -z "$MEETING_ID" ] || [ "$MEETING_ID" == "null" ]; then
    echo "ERROR: Could not find meetingId for room: $ROOM_NAME"
    exit 1
fi

echo "Meeting ID: $MEETING_ID"

# Upload files to file-service
# Path structure: /roomName/sessionId/filename.ext
UPLOAD_PATH="${ROOM_NAME}/${SESSION_ID}"

cd "$RECORDING_DIR"

for file in *; do
    if [ -f "$file" ]; then
        echo "Uploading: $file"

        # Upload to file-service with structured path
        curl -X POST \
            -H "Content-Type: multipart/form-data" \
            -F "file=@$file" \
            "${FILE_SERVICE_URL}/files/structured/${MEETING_ID}?path=/${UPLOAD_PATH}/" \
            || echo "WARNING: Failed to upload $file"
    fi
done

# Send STOPPED webhook to meeting-service
echo "Sending STOPPED webhook..."
curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-Webhook-Secret: ${WEBHOOK_SECRET}" \
    -d "{
        \"eventType\": \"STOPPED\",
        \"roomName\": \"${ROOM_NAME}\",
        \"sessionId\": \"${SESSION_ID}\",
        \"timestamp\": $(date +%s)
    }" \
    "${MEETING_SERVICE_URL}/webhooks/jitsi/recording"

echo "=== Jibri Finalize Script Completed ==="
```

**Make it executable:**

```bash
sudo chmod +x /usr/local/bin/jibri-finalize.sh
```

#### 3. Jibri Configuration

Update `/etc/jitsi/jibri/jibri.conf`:

```hocon
jibri {
    recording {
        recordings-directory = "/tmp/recordings"
        finalize-script = "/usr/local/bin/jibri-finalize.sh"
    }

    api {
        http {
            external-api-port = 2222
            internal-api-port = 3333
        }
    }
}
```

#### 4. Environment Variables

Add to Jibri container/systemd environment:

```bash
# In docker-compose.yml or /etc/systemd/system/jibri.service.d/override.conf
FILE_SERVICE_URL=http://file-service:2027
MEETING_SERVICE_URL=http://meeting-service:2031
WEBHOOK_SECRET=your-secret-key-here
```

### Recording Webhook Events

#### STARTED Event

**Sent by:** Jibri (when recording starts)

```json
POST /webhooks/jitsi/recording
{
  "eventType": "STARTED",
  "roomName": "abc-defg-hij",
  "sessionId": "20250105-143022-abc123",
  "timestamp": 1704462622
}
```

**Backend action:**
- Creates `MeetingRecording` entity with `status=PROCESSING`
- Stores sessionId for tracking

#### STOPPED Event

**Sent by:** Jibri finalize script (after files uploaded)

```json
POST /webhooks/jitsi/recording
{
  "eventType": "STOPPED",
  "roomName": "abc-defg-hij",
  "sessionId": "20250105-143022-abc123",
  "timestamp": 1704463822
}
```

**Backend action:**
- Updates `MeetingRecording` status
- Recording now available for download

#### FAILED Event

**Sent by:** Jibri (if recording fails)

```json
POST /webhooks/jitsi/recording
{
  "eventType": "FAILED",
  "roomName": "abc-defg-hij",
  "sessionId": "20250105-143022-abc123",
  "error": "Encoding failed",
  "timestamp": 1704463922
}
```

**Backend action:**
- Updates `MeetingRecording` status to `FAILED`
- Stores error message

### Retrieving Recording Files

#### Query by Meeting ID

```bash
GET /file-service/metadata?referenceId={meetingId}
```

**Response:**

```json
[
  {
    "id": 123,
    "filename": "video.mp4",
    "path": "/abc-defg-hij/20250105-143022-abc123/video.mp4",
    "mimeType": "video/mp4",
    "size": 45678901,
    "uploadedAt": "2025-01-05T14:35:22Z"
  },
  {
    "id": 124,
    "filename": "chat.json",
    "path": "/abc-defg-hij/20250105-143022-abc123/chat.json",
    "mimeType": "application/json",
    "size": 12345,
    "uploadedAt": "2025-01-05T14:35:23Z"
  }
]
```

#### Download File

```bash
GET /file-service/files/{fileId}/download
```

Returns the actual file content with proper Content-Type headers.

### Testing Recording Flow

#### 1. Start a Meeting

```bash
curl -X POST http://meeting-service:2031/api/meetings \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {token}" \
  -d '{"title": "Test Meeting", "maxDurationMinutes": 60}'
```

#### 2. Join Meeting and Start Recording

- Open Jitsi Meet: `https://meet.yourdomain.com/abc-defg-hij`
- Click record button
- Jibri receives recording request

#### 3. Stop Recording

- Click stop recording button
- Jibri runs finalize script
- Files uploaded to file-service
- STOPPED webhook sent to backend

#### 4. Verify Files

```bash
# Get meeting ID from step 1 response
MEETING_ID=123

# Query uploaded files
curl http://file-service:2027/metadata?referenceId=${MEETING_ID}
```

---

## Debugging

### Enable Logging

Edit Prosody config:

```lua
log = {
    info = "/var/log/prosody/prosody.log";
    debug = "/var/log/prosody/prosody.log";
}
```

### Watch Webhook Traffic

```bash
sudo tail -f /var/log/prosody/prosody.log | grep -i webhook
```

**Expected output:**

```
INFO  - Jitsi Webhooks Module loaded
INFO  - Room created: abc-defg-hij
INFO  - Room configuration received for: abc-defg-hij
INFO  - Access granted: room=abc-defg-hij, user=user@domain.com
INFO  - User joined: room=abc-defg-hij, user=John Doe
INFO  - User left: room=abc-defg-hij, user=John Doe
INFO  - Room destroyed: abc-defg-hij
```

### Test Webhook Endpoints

From Prosody server:

```bash
# Test room-created
curl -X POST https://api.domain.com/webhooks/jitsi/room-created \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your-secret" \
  -d '{"roomName": "test", "roomJid": "test@conf.domain", "timestamp": 1234567890}'

# Expected: 200 OK with room configuration JSON

# Test validate-access
curl -X POST https://api.domain.com/webhooks/jitsi/validate-access \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your-secret" \
  -d '{"roomName": "test", "userJid": "user@domain.com", "userName": "Test", "timestamp": 1234567890}'

# Expected: 200 OK with {"allowed": true/false, ...}
```

---

## Troubleshooting

### Common Module Issues

**Problem:** "Webhook secret not configured - accepting all requests"
**Solution:** Set `jitsi_webhook_secret` in Prosody config

**Problem:** "Access denied: server unavailable"
**Solution:**
- Check backend is running: `curl http://backend:2031/actuator/health`
- Verify network connectivity from Prosody server
- Check firewall rules

**Problem:** "Private meeting: no authentication token"
**Solution:**
- Ensure JWT passed in URL: `?jwt={token}`
- Check Prosody has `authentication = "token"` configured
- Verify `app_secret` matches Keycloak client secret

**Problem:** Duration timer not working
**Solution:**
- Check backend returns `maxDurationMinutes` in `/room-created` response
- Look for "Scheduled room destruction" in Prosody logs
- Verify timer isn't cancelled by room destruction before expiry

### Recording Issues

**Problem:** Files not uploading
**Solutions:**
- Check Jibri logs: `journalctl -u jibri -f`
- Check finalize script logs: `tail -f /var/log/jitsi/jibri/finalize.log`
- Verify file-service connectivity: `curl http://file-service:2027/actuator/health`
- Check script has execute permissions: `ls -l /usr/local/bin/jibri-finalize.sh`

**Problem:** Webhook not received
**Solutions:**
- Check meeting-service logs: `docker logs meeting-service -f`
- Verify webhook secret matches:
  ```bash
  # In finalize script
  WEBHOOK_SECRET=your-secret

  # In application.yml
  jitsi.webhook.secret: your-secret
  ```

**Problem:** Recording status stuck in PROCESSING
**Solutions:**
- Check if finalize script executed successfully
- Verify STOPPED webhook was sent and received
- Check file-service for uploaded files: `GET /metadata?referenceId={meetingId}`
- Look for errors in Jibri logs

**Problem:** MeetingId not found error
**Solution:**
- Verify meeting exists in database with that roomName
- Check API endpoint is accessible: `curl http://meeting-service:2031/api/meetings/room/{roomName}`
- Ensure JWT authentication is configured if endpoint requires it

---

## Security Considerations

### Production Security Checklist

✅ **Webhook Authentication**
- Always set `jitsi_webhook_secret` (strong, random secret)
- Rotate secrets periodically
- Use HTTPS for webhook URLs in production

✅ **Network Security**
- Ensure file-service is only accessible from Jibri containers
- Use internal networks for Prosody ↔ Backend communication
- Restrict Jibri access to file-service

✅ **File Validation**
- File-service should validate file types and sizes
- Implement virus scanning for uploaded recordings
- Set upload size limits in Jibri config

✅ **Access Control**
- Only authenticated users should download recordings
- Verify user permissions before serving files
- Use signed URLs with expiration for file downloads

✅ **JWT Security (Private Meetings)**
- Use strong Keycloak client secrets
- Set appropriate JWT expiration times
- Validate JWT signature on every request
- Never expose secrets in logs or error messages

✅ **Monitoring**
- Monitor webhook failures and retry logic
- Alert on suspicious activity (repeated failed joins)
- Track recording failures and disk space
- Monitor Prosody logs for errors

---

## See Also

- **[Basic Module](../prosody-plugin/README.md)** - Simpler alternative without participant tracking
- **[Jitsi UI Plugin](../jitsi-plugin/README.md)** - Frontend configuration
- **[Main Documentation](../README.md)** - Complete service documentation
