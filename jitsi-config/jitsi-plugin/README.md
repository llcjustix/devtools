# Jitsi Meet Room Configuration Plugin

This plugin enables Jitsi Meet to receive and apply room-specific configuration from your backend via Prosody XMPP messages.

## How It Works

1. **User joins room** → Prosody webhook calls your backend
2. **Backend returns config** → Prosody stores settings in room data
3. **Prosody sends XMPP message** → Plugin receives ROOM_CONFIG message
4. **Plugin applies settings** → Jitsi interface is configured

## Installation

### Step 1: Copy Plugin to Jitsi Server

```bash
# Copy plugin to Jitsi Meet server
sudo cp room-config-plugin.js /usr/share/jitsi-meet/libs/

# Set correct permissions
sudo chown www-data:www-data /usr/share/jitsi-meet/libs/room-config-plugin.js
sudo chmod 644 /usr/share/jitsi-meet/libs/room-config-plugin.js
```

### Step 2: Load Plugin in Jitsi

Edit `/usr/share/jitsi-meet/index.html` and add before the closing `</body>` tag:

```html
<!-- Custom Room Configuration Plugin -->
<script src="libs/room-config-plugin.js"></script>
```

### Step 3: Update Jitsi Config (Optional)

Edit `/etc/jitsi/meet/meet.learnx.uz-config.js`:

```javascript
var config = {
    // ... existing config ...

    // Allow custom toolbar customization
    customToolbarButtons: [],

    // Disable default buttons (plugin will re-enable based on config)
    // toolbarButtons: [
    //     'camera', 'chat', 'closedcaptions', 'desktop', 'download', 'embedmeeting',
    //     'etherpad', 'feedback', 'filmstrip', 'fullscreen', 'hangup', 'help',
    //     'highlight', 'invite', 'linktosalesforce', 'livestreaming', 'microphone',
    //     'noisesuppression', 'participants-pane', 'profile', 'raisehand', 'recording',
    //     'security', 'select-background', 'settings', 'shareaudio', 'sharedvideo',
    //     'shortcuts', 'stats', 'tileview', 'toggle-camera', 'videoquality', 'whiteboard'
    // ],
};
```

### Step 4: Restart Jitsi Services

```bash
sudo systemctl restart nginx
sudo systemctl restart prosody
sudo systemctl restart jicofo
sudo systemctl restart jitsi-videobridge2
```

## Supported Configuration Options

The plugin listens for `ROOM_CONFIG` XMPP messages and applies these settings:

### Core Features
- `chatEnabled` - Enable/disable chat
- `whiteboardEnabled` - Enable/disable whiteboard
- `screenShareEnabled` - Enable/disable screen sharing
- `recordingEnabled` - Enable/disable recording
- `muteOnJoin` - Auto-mute audio on join
- `videoOffOnJoin` - Auto-disable video on join
- `meetingTitle` - Set room subject/title

### Participant Features
- `reactionsEnabled` - Enable/disable emoji reactions
- `raiseHandEnabled` - Enable/disable raise hand
- `privateMessagesEnabled` - Enable/disable private messages
- `tileViewEnabled` - Enable/disable tile view

### Media Features
- `liveStreamingEnabled` - Enable/disable YouTube/Facebook streaming
- `virtualBackgroundsEnabled` - Enable/disable virtual backgrounds
- `noiseSuppressionEnabled` - Enable/disable noise suppression
- `e2eeEnabled` - Enable end-to-end encryption

### Moderation Features
- `pollsEnabled` - Enable/disable polls
- `breakoutRoomsEnabled` - Enable/disable breakout rooms
- `speakerStatsEnabled` - Enable/disable speaker statistics
- `securityEnabled` - Enable/disable security options

### UI Features
- `closedCaptionsEnabled` - Enable/disable closed captions
- `sharedDocumentEnabled` - Enable/disable Etherpad

## Testing

1. Create a meeting with specific settings in your backend
2. Join the Jitsi room
3. Open browser console (F12)
4. Look for `[RoomConfig]` log messages
5. Verify buttons are hidden/shown based on configuration

Example console output:
```
[RoomConfig] Plugin loading...
[RoomConfig] Jitsi Meet API available, initializing...
[RoomConfig] Message handler registered
[RoomConfig] Received configuration: {chatEnabled: false, whiteboardEnabled: true, ...}
[RoomConfig] Disabling chat
[RoomConfig] Configuration applied successfully
```

## Troubleshooting

### Plugin Not Loading
- Check browser console for errors
- Verify script path in index.html
- Ensure file permissions are correct
- Clear browser cache

### Configuration Not Applied
- Check Prosody logs: `sudo journalctl -u prosody -f`
- Verify webhook is working (check backend logs)
- Ensure XMPP message handler is registered (check console)
- Verify ROOM_CONFIG message format

### Buttons Still Visible
- Some buttons require additional CSS hiding
- Check button `data-testid` attribute in DOM
- Add custom CSS rules if needed

## Advanced Customization

You can extend the plugin to handle additional settings:

```javascript
// Add custom configuration handler
if (config.customFeature === true) {
    console.log('[RoomConfig] Enabling custom feature');
    // Your custom logic here
}
```

## Security

- Configuration is sent via encrypted XMPP WebSocket (wss://)
- Settings are NOT visible in URL parameters
- Only users who join the room receive the configuration
- Prosody webhook validates requests via secret header

## Related Files

- **Backend**: `MeetingService.java` - Generates configuration
- **Prosody Module**: `prosody-plugin/mod_muc_webhook.lua` - Sends XMPP messages
- **Database**: `meeting_settings` table - Stores configuration

## Support

For issues or questions, check:
1. Backend logs: `journalctl -u meeting-service -f`
2. Prosody logs: `journalctl -u prosody -f`
3. Jitsi logs: `/var/log/jitsi/`
4. Browser console (F12)
