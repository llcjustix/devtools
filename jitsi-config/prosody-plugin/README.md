# Prosody Basic Webhook Module

**Module:** `mod_muc_webhook.lua`
**Type:** Basic room configuration and access validation
**Use Case:** Simple Jitsi integration without participant tracking

## Overview

This is the **basic** Prosody module for meeting-service integration. It provides essential room configuration and access validation, but does **not** track participants or enforce duration limits.

**Use this module when:**
- You only need room configuration from backend
- You only need access control (block cancelled/expired meetings)
- You don't need participant tracking or duration logs
- You don't need automatic duration enforcement

**For full features, use:** [`prosody-modules/mod_jitsi_webhooks.lua`](../prosody-modules/README.md) (recommended)

## Features

### ✅ Implemented
- **Room Configuration** - Fetches config from backend when room created
- **Access Validation** - Blocks users from joining cancelled/expired meetings
- **Room Config to UI** - Sends `ROOM_CONFIG` message to Jitsi frontend
- **Auto-Recording Trigger** - Starts recording if `autoRecord` enabled

### ❌ Not Implemented
- No participant tracking (user-joined, user-left webhooks commented out)
- No duration enforcement (no Prosody timer)
- No moderator tracking (moderator-changed webhook not implemented)
- No room-destroyed webhook (commented out)

## Installation

### 1. Copy Module to Prosody

```bash
sudo cp mod_muc_webhook.lua /usr/share/jitsi-meet/prosody-plugins/
sudo chown root:root /usr/share/jitsi-meet/prosody-plugins/mod_muc_webhook.lua
sudo chmod 644 /usr/share/jitsi-meet/prosody-plugins/mod_muc_webhook.lua
```

### 2. Configure Prosody

Edit Prosody config:
```bash
sudo nano /etc/prosody/conf.d/meet.yourdomain.com.cfg.lua
```

Add to conference component:
```lua
Component "conference.meet.yourdomain.com" "muc"
    modules_enabled = {
        "muc_meeting_id";
        "muc_domain_mapper";
        "muc_webhook";  -- Add this
    }

    -- Webhook configuration
    muc_webhook_url = "https://api.yourdomain.com/webhooks/jitsi"
    muc_webhook_secret = "your-secret-key-here"
    muc_webhook_timeout = 5
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

## Webhook Endpoints Used

This module calls these backend endpoints:

### 1. Room Created - Get Configuration
```lua
POST /webhooks/jitsi/room-created
{
  "roomName": "abc-defg-hij",
  "roomJid": "abc-defg-hij@conference.domain",
  "timestamp": 1234567890
}
```

**Backend returns:**
```json
{
  "moderators": ["admin@domain.com"],
  "maxParticipants": 50,
  "chatEnabled": true,
  "recordingEnabled": true,
  "whiteboardEnabled": true,
  "screenShareEnabled": true,
  "lobbyEnabled": false,
  "muteOnJoin": false,
  "videoOffOnJoin": false,
  "autoRecord": false,
  "reactionsEnabled": true,
  ... // 50+ settings
}
```

**Module applies:**
- Sets moderators (owner affiliation)
- Sets max participants limit
- Sets password (if provided)
- Stores all settings in `room._data` for UI plugin
- Sends `ROOM_CONFIG` message to Jitsi frontend

### 2. Validate Access - Before Join
```lua
POST /webhooks/jitsi/validate-access
{
  "roomName": "abc-defg-hij",
  "userJid": "user@domain.com",
  "userName": "John Doe",
  "timestamp": 1234567890
}
```

**Backend validates:**
- Meeting exists
- Meeting not cancelled
- Meeting not completed
- Meeting not expired (duration limit)
- For private meetings: user is invited

**Backend returns:**
```json
{
  "allowed": true/false,
  "reason": "Meeting has been cancelled",
  "meetingTitle": "Team Standup"
}
```

**Module actions:**
- If `allowed: false` → Blocks user with error message
- If `allowed: true` → Allows user to join

## Room Configuration Details

### Prosody MUC Settings Applied

```lua
room:set_members_only(config.membersOnly)     -- Require membership
room:set_moderated(config.moderated)          -- Voice moderation
room:set_persistent(config.persistent)        -- Persist after empty
room:set_hidden(config.hidden)                -- Hide from room list
room:set_public(config.publicRoom)            -- Public directory
room:set_whois(config.whois)                  -- JID visibility
room:set_password(config.password)            -- Room password
room._data.max_participants = config.maxParticipants
```

### Settings Sent to Jitsi UI

The module sends a `ROOM_CONFIG` XMPP message to each user on join:

```lua
{
  type: "ROOM_CONFIG",
  config: {
    chatEnabled: true/false,
    whiteboardEnabled: true/false,
    screenShareEnabled: true/false,
    recordingEnabled: true/false,
    muteOnJoin: true/false,
    videoOffOnJoin: true/false,
    meetingTitle: "Meeting Title",
    reactionsEnabled: true/false,
    raiseHandEnabled: true/false,
    ... // All settings from backend
  }
}
```

**Note:** Requires [Jitsi Room Config Plugin](../jitsi-plugin/README.md) to apply these settings to the UI.

### Auto-Recording Trigger

If `autoRecord: true` and `recordingEnabled: true`:

```lua
-- On first user join, module sends:
{
  type: "START_RECORDING",
  auto: true
}
```

This triggers Jibri to start recording automatically.

## Limitations

### What This Module Cannot Do

❌ **No participant tracking** - User joins/leaves are not logged
❌ **No duration enforcement** - Rooms don't auto-destroy after duration expires
❌ **No meeting lifecycle** - Backend doesn't know when meeting started/ended
❌ **No moderator tracking** - Moderator changes not logged
❌ **No participant duration** - Can't calculate how long users stayed

**To enable these features, use:** [`prosody-modules/mod_jitsi_webhooks.lua`](../prosody-modules/README.md)

### Commented Out Webhooks

The module has these webhooks commented out (lines 376-419):

```lua
-- Hook: User left (COMMENTED OUT)
module:hook("muc-occupant-left", function(event)
    -- Optional: Send webhook to backend
    -- Uncomment if you need to track user departures
end)

-- Hook: Room destroyed (COMMENTED OUT)
module:hook("muc-room-destroyed", function(event)
    -- Optional: Notify backend when room is destroyed
    -- Uncomment if you need to track room lifecycle
end)
```

**Why commented out:**
- To reduce webhook traffic
- Basic module is for minimal integration
- For full tracking, use complete module instead

## Configuration Options

All options set in Prosody config:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `muc_webhook_url` | string | (required) | Base URL for webhooks (e.g., `http://api:2031/webhooks/jitsi`) |
| `muc_webhook_secret` | string | (none) | Shared secret for webhook authentication (sent in `X-Webhook-Secret` header) |
| `muc_webhook_timeout` | number | 5 | HTTP request timeout in seconds |

## Troubleshooting

### Check Module Loaded

```bash
sudo prosodyctl about | grep muc_webhook
```

Should show: `muc_webhook` in loaded modules list.

### Enable Debug Logging

```bash
sudo nano /etc/prosody/prosody.cfg.lua
```

Add:
```lua
log = {
    debug = "/var/log/prosody/prosody.log";
}
```

Restart and check logs:
```bash
sudo systemctl restart prosody
sudo tail -f /var/log/prosody/prosody.log | grep webhook
```

### Test Webhook Connectivity

From Prosody server:
```bash
curl -X POST https://api.yourdomain.com/webhooks/jitsi/room-created \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: your-secret" \
  -d '{"roomName": "test-room", "roomJid": "test@conf.domain", "timestamp": 1234567890}'
```

Expected: `200 OK` with room configuration JSON.

## Migration to Complete Module

To upgrade to full participant tracking and duration enforcement:

1. **Install complete module:**
   ```bash
   sudo cp ../prosody-modules/mod_jitsi_webhooks.lua /usr/share/jitsi-meet/prosody-plugins/
   ```

2. **Update Prosody config:**
   ```lua
   Component "conference.meet.yourdomain.com" "muc"
       modules_enabled = {
           "muc_meeting_id";
           "muc_domain_mapper";
           "jitsi_webhooks";  -- Changed from muc_webhook
       }

       -- Update config variable names
       jitsi_webhook_url = "https://api.yourdomain.com/webhooks/jitsi"
       jitsi_webhook_secret = "your-secret-key-here"
       jitsi_webhook_timeout = 5
       jitsi_file_service_url = "http://file-service:2027"  -- NEW
   ```

3. **Restart Prosody:**
   ```bash
   sudo systemctl restart prosody
   ```

**No backend changes needed** - Complete module uses same webhook endpoints plus additional ones.

## See Also

- [Complete Module Documentation](../prosody-modules/README.md) - Full features with participant tracking
- [Jitsi Plugin Documentation](../jitsi-plugin/README.md) - Frontend UI configuration
- [Main Service Documentation](../README.md) - Backend API and architecture
