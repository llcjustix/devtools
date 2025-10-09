// Custom config overrides for JustIX Academy
// This file contains configuration that disables default Jitsi recording UI
// and enforces backend-controlled recording logic

// Force HTTP for local development (override generated config.js)
// This fixes the "You have been disconnected" error when DISABLE_HTTPS=1
// Use window.location.protocol to match the page protocol
var protocol = window.location.protocol === 'https:' ? 'https:' : 'http:';
var wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
config.bosh = protocol + '//' + window.location.host + '/http-bind';
config.websocket = wsProtocol + '//' + window.location.host + '/xmpp-websocket';

// RoomConfiguration settings injection from backend (via JWT or API)
// These settings can be overridden dynamically when room config is loaded
// Format: window.ROOM_CONFIG = { ... } will override these defaults

// Function to apply room configuration from backend
window.applyRoomConfiguration = function(roomConfig) {
    if (!roomConfig) return;

    // Meeting title - display in UI instead of room name
    if (roomConfig.meetingTitle) {
        config.subject = roomConfig.meetingTitle;
        console.log('[JustIX] Meeting title set:', roomConfig.meetingTitle);
    }

    // Recording settings
    if (roomConfig.recordingEnabled !== undefined) {
        config.recordingService.enabled = roomConfig.recordingEnabled;
    }

    // Chat settings
    if (roomConfig.chatEnabled !== undefined) {
        config.disableChat = !roomConfig.chatEnabled;
    }

    // Whiteboard settings
    if (roomConfig.whiteboardEnabled !== undefined) {
        config.whiteboard.enabled = roomConfig.whiteboardEnabled;
    }

    // Lobby settings
    if (roomConfig.lobbyEnabled !== undefined) {
        config.enableLobbyChat = roomConfig.lobbyEnabled;
    }

    // Screensharing settings
    if (roomConfig.screensharingEnabled !== undefined) {
        config.disableDesktopSharing = !roomConfig.screensharingEnabled;
    }

    // Raise hand settings
    if (roomConfig.raiseHandEnabled !== undefined) {
        config.disableRaiseHand = !roomConfig.raiseHandEnabled;
    }

    // Private messages settings
    if (roomConfig.privateMessagesEnabled !== undefined) {
        config.disablePrivateMessages = !roomConfig.privateMessagesEnabled;
    }

    // Reactions settings
    if (roomConfig.reactionsEnabled !== undefined) {
        config.disableReactions = !roomConfig.reactionsEnabled;
    }

    // Polls settings
    if (roomConfig.pollsEnabled !== undefined) {
        config.disablePolls = !roomConfig.pollsEnabled;
    }

    // Breakout rooms settings
    if (roomConfig.breakoutRoomsEnabled !== undefined) {
        config.breakoutRooms.enabled = roomConfig.breakoutRoomsEnabled;
    }

    // Virtual backgrounds settings
    if (roomConfig.virtualBackgroundEnabled !== undefined) {
        config.disableVirtualBackground = !roomConfig.virtualBackgroundEnabled;
    }

    // Video quality settings
    if (roomConfig.maxVideoQuality !== undefined) {
        config.resolution = parseInt(roomConfig.maxVideoQuality) || 720;
    }

    // Participant limits
    if (roomConfig.maxParticipants !== undefined && roomConfig.maxParticipants > 0) {
        config.maxParticipants = roomConfig.maxParticipants;
    }

    // Start muted settings
    if (roomConfig.startAudioMuted !== undefined) {
        config.startWithAudioMuted = roomConfig.startAudioMuted;
    }

    if (roomConfig.startVideoMuted !== undefined) {
        config.startWithVideoMuted = roomConfig.startVideoMuted;
    }

    // Livestreaming settings
    if (roomConfig.livestreamingEnabled !== undefined) {
        config.liveStreaming.enabled = roomConfig.livestreamingEnabled;
    }

    console.log('[JustIX] Room configuration applied:', roomConfig);
};

// Listen for room config from parent window or API
window.addEventListener('message', function(event) {
    if (event.data && event.data.type === 'ROOM_CONFIG') {
        window.applyRoomConfiguration(event.data.config);
    }
});

// Check if room config was embedded in JWT
if (window.ROOM_CONFIG) {
    window.applyRoomConfiguration(window.ROOM_CONFIG);
}

// Disable file recording service (Dropbox integration)
config.fileRecordingsEnabled = false;
config.dropbox = {
    appKey: '', // Disabled
};

// Hide recording-related UI that asks where to save
config.fileRecordingsServiceEnabled = false;
config.fileRecordingsServiceSharingEnabled = false;

// Local recording (browser-based) - disable to prevent confusion
config.localRecording = {
    disable: true,
    notifyAllParticipants: false,
    disableSelfRecording: true
};

// Recording button will still appear, but will use Jibri (our backend logic)
// No UI prompts for "where to save" - Jibri handles upload automatically
config.recordingService = {
    enabled: true,
    sharingEnabled: false, // Don't show sharing options after recording
    hideStorageWarning: true // Hide storage warnings
};

// Disable livestreaming UI (not needed for academy)
config.liveStreaming = {
    enabled: false
};

// Disable transcription (not needed)
config.transcription = {
    enabled: false
};

// Custom branding
config.defaultLocalDisplayName = 'Me';
config.defaultRemoteDisplayName = 'Participant';
config.defaultLogoUrl = 'images/learnx-watermark.svg';

// Toolbar buttons - hide unnecessary features
config.toolbarButtons = [
    'camera',
    'chat',
    'closedcaptions',
    'desktop',
    'download',
    'embedmeeting',
    'etherpad',
    'feedback',
    'filmstrip',
    'fullscreen',
    'hangup',
    'help',
    'highlight',
    'invite',
    'linktosalesforce',
    'livestreaming', // Hidden via liveStreaming.enabled = false
    'microphone',
    'noisesuppression',
    'participants-pane',
    'profile',
    'raisehand',
    'recording', // Enabled - uses Jibri backend logic
    'security',
    'select-background',
    'settings',
    'shareaudio',
    'sharedvideo',
    'shortcuts',
    'stats',
    'tileview',
    'toggle-camera',
    'videoquality',
    'whiteboard'
];

// Disable features not needed
config.disableProfile = false;
config.disableInviteFunctions = false;

// Welcome page customization
config.enableWelcomePage = true;
config.enableClosePage = false;

// Prejoin page
config.prejoinConfig = {
    enabled: true,
    hideDisplayName: false
};

// ============================================
// AUTHENTICATION HANDLING
// ============================================

// Handle JWT token from URL parameter
(function() {
    const urlParams = new URLSearchParams(window.location.search);
    const jwtToken = urlParams.get('jwt');

    if (jwtToken) {
        console.log('[JustIX] JWT token found in URL');
        // Store JWT for connection - Jitsi will use it automatically
        config.jwt = jwtToken;
    }

    // Listen for authentication failures and redirect to login
    // Use JitsiMeetJS events which fire earlier than APP events
    let redirectHandled = false;

    function setupAuthenticationListener() {
        console.log('[JustIX] Setting up authentication listener');

        // Try to hook into JitsiMeetJS events
        if (typeof JitsiMeetJS !== 'undefined') {
            console.log('[JustIX] JitsiMeetJS available, setting up listeners');

            // Listen for connection events
            const JitsiConnectionEvents = JitsiMeetJS.events.connection;
            const JitsiConferenceEvents = JitsiMeetJS.events.conference;

            // Override the connection init to add our listener
            const originalConnection = JitsiMeetJS.JitsiConnection;
            if (originalConnection) {
                const origPrototype = originalConnection.prototype.connect;
                originalConnection.prototype.connect = function() {
                    console.log('[JustIX] Connection initiated');

                    // Add error listener
                    this.addEventListener(JitsiConnectionEvents.CONNECTION_FAILED, function(error) {
                        console.log('[JustIX] Connection failed event:', error);
                        if (error === 'connection.passwordRequired' && !redirectHandled) {
                            redirectHandled = true;
                            handleAuthenticationRequired();
                        }
                    });

                    // Call original
                    return origPrototype.apply(this, arguments);
                };
            }
        }

        // Also try APP-based listeners as fallback
        if (typeof APP !== 'undefined' && APP.conference) {
            console.log('[JustIX] APP.conference available, adding listeners');

            APP.conference.addListener('CONFERENCE_FAILED', function(errorCode, error) {
                console.log('[JustIX] Conference failed:', errorCode, error);
                if ((errorCode === 'conference.authenticationRequired' ||
                     errorCode === 'connection.passwordRequired') && !redirectHandled) {
                    redirectHandled = true;
                    handleAuthenticationRequired();
                }
            });

            APP.conference.addListener('CONNECTION_FAILED', function(error) {
                console.log('[JustIX] Connection failed:', error);
                if (error === 'connection.passwordRequired' && !redirectHandled) {
                    redirectHandled = true;
                    handleAuthenticationRequired();
                }
            });
        }
    }

    // Try to setup listeners when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupAuthenticationListener);
    } else {
        setupAuthenticationListener();
    }

    // Also try when window loads (fallback)
    window.addEventListener('load', setupAuthenticationListener);

    function handleAuthenticationRequired() {
        console.log('[JustIX] Authentication required - redirecting to login');

        // Get room name from URL
        const pathParts = window.location.pathname.split('/').filter(p => p);
        const roomName = pathParts[pathParts.length - 1];

        if (!roomName) {
            console.error('[JustIX] Cannot determine room name for redirect');
            return;
        }

        // Redirect to login page
        const loginUrl = `http://localhost:2031/login.html?room=${roomName}&returnUrl=${encodeURIComponent(window.location.href)}`;
        console.log('[JustIX] Redirecting to:', loginUrl);

        setTimeout(function() {
            window.location.href = loginUrl;
        }, 1000); // Small delay to show error message
    }
})();
