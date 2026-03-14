// Custom config overrides for LearnX Meets
// This file contains configuration that disables default Jitsi recording UI
// and enforces backend-controlled recording logic

// DYNAMIC MEETING SERVICE URL DETECTION (via API gateway)
const meetingServiceUrl = (() => {
    if (window.MEETING_SERVICE_URL) return window.MEETING_SERVICE_URL;
    const base = `${window.location.protocol}//${window.location.hostname.replace('meet.', '')}`;
    return base + '/meeting-service';
})();

console.log('[LearnX Meets] Meeting Service URL:', meetingServiceUrl);

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
        console.log('[LearnX Meets] Meeting title set:', roomConfig.meetingTitle);
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

    console.log('[LearnX Meets] Room configuration applied:', roomConfig);
};

// Listen for room config from parent window or API (same-origin only)
window.addEventListener('message', function(event) {
    if (event.origin !== window.location.origin) return;
    if (event.data && event.data.type === 'ROOM_CONFIG') {
        window.applyRoomConfiguration(event.data.config);
    }
});

// Check if room config was embedded in JWT
if (window.ROOM_CONFIG) {
    window.applyRoomConfiguration(window.ROOM_CONFIG);
}

// Auto-fetch meeting info from backend to set title and room config
(function() {
    var roomName = window.location.pathname.replace(/^\//, '').split('/')[0];
    if (roomName && roomName.length > 0 && roomName !== 'welcome.html' && roomName !== 'schedule.html' && roomName !== 'login.html') {
        fetch(meetingServiceUrl + '/api/v1/meetings/by-room/' + encodeURIComponent(roomName))
            .then(function(r) { return r.ok ? r.json() : null; })
            .then(function(meeting) {
                if (meeting && meeting.title) {
                    config.subject = meeting.title;
                    // Also update document title
                    document.title = meeting.title + ' | LearnX Meets';
                    console.log('[LearnX Meets] Meeting title loaded:', meeting.title);
                    // Apply full room config if settings exist
                    if (meeting.settings) {
                        window.applyRoomConfiguration(meeting.settings);
                    }
                }
            })
            .catch(function(e) { console.log('[LearnX Meets] Could not fetch meeting info:', e); });
    }
})();

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

// Disable transcription (not needed yet)
config.transcription = {
    enabled: false
};

// Excalidraw collaborative whiteboard
// WHITEBOARD_COLLAB_SERVER_PUBLIC_URL env var is auto-injected by jitsi-web entrypoint
if (!config.whiteboard || !config.whiteboard.collabServerBaseUrl) {
    config.whiteboard = {
        enabled: true,
        collabServerBaseUrl: window.location.origin
    };
}

// Custom branding
config.defaultLocalDisplayName = 'Me';
config.defaultRemoteDisplayName = 'Participant';
config.defaultLogoUrl = 'images/learnx-watermark.svg';

// Toolbar buttons - only essential features (no tile view toggle)
config.toolbarButtons = [
    'camera',
    'chat',
    'closedcaptions',
    'desktop',
    'filmstrip',
    'fullscreen',
    'hangup',
    'microphone',
    'noisesuppression',
    'participants-pane',
    'profile',
    'raisehand',
    'reactions',
    'recording',
    'security',
    'select-background',
    'settings',
    'shareaudio',
    'sharedvideo',
    'toggle-camera',
    'videoquality',
    'whiteboard'
];

// Always use tile view layout (Google Meet style grid)
config.disableTileView = false;
config.startInTileView = true; // Start in tile view by default

// Hide room name / meeting ID from conference header
config.hideConferenceSubject = true;
config.hideConferenceTimer = false;

// Disable connection/performance indicator (the stats icon on top)
config.connectionIndicators = {
    disabled: true
};

// Conference info header — only show essential items (no subject/room name)
config.conferenceInfo = {
    alwaysVisible: ['recording'],
    autoHide: ['conference-timer', 'participants-count', 'raised-hands-count']
};

// ========================================
// REACTIONS & SOUNDS
// ========================================
config.disableReactions = false;
config.disableSelfViewSettings = false;
config.reactions = {
    enabled: true
};
config.giphy = {
    enabled: true,  // Enable GIF reactions for richer expression
    displayMode: 'tile' // 'tile' shows in chat, 'all' shows full-screen
};
// Sound settings — users can toggle in Settings > Sounds
// Moderators can mute reaction sounds for all participants
config.disableSounds = false;
config.soundsReactions = true; // Enable reaction sounds by default

// ========================================
// GENERAL SETTINGS
// ========================================
config.disableProfile = false;
config.disableInviteFunctions = false;
config.enableWelcomePage = false;
config.enableClosePage = false;

// Prejoin page — ask audio/video preferences before joining
config.prejoinConfig = {
    enabled: true,
    hideDisplayName: false,
    hideExtraJoinButtons: ['no-audio', 'by-phone'] // Remove "join without audio" from dropdown, keep it simple
};

// ========================================
// PER-USER SETTINGS PERSISTENCE
// Jitsi stores user preferences in localStorage automatically:
// - Audio/video device selection
// - Display name
// - Virtual background
// - Audio output device
// - Start muted preferences
// - Tile view preference
// These persist across meetings for the same browser/user.
// ========================================
config.doNotStoreRoom = true; // Don't store room names in localStorage for privacy

// Hangup menu: moderators see "Leave" + "End meeting for all" (like Zoom)
// Regular participants only see "Leave meeting"
config.hangupMenuEnabled = true;

// ========================================
// MEETING LEAVE/END HANDLER
// On leave or "end for all" → redirect to welcome page
// ========================================
(function() {
    'use strict';

    let hasRedirected = false;
    const roomPath = window.location.pathname;

    const redirectToWelcome = () => {
        if (hasRedirected) return;
        hasRedirected = true;
        console.log('[LearnX Meets] Redirecting to welcome page');
        window.location.replace('/welcome.html');
    };

    // 1. Intercept Jitsi's post-hangup navigation (pushState/replaceState to '/' or close page)
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;

    const interceptNav = (url) => {
        if (typeof url === 'string') {
            const cleaned = url.replace(window.location.origin, '');
            if (cleaned === '/' || cleaned === '' || cleaned === '#' ||
                cleaned.includes('close3.html') || cleaned.includes('close.html') ||
                cleaned.includes('static/close')) {
                redirectToWelcome();
                return true;
            }
        }
        return false;
    };

    history.pushState = function() {
        if (!interceptNav(arguments[2])) originalPushState.apply(this, arguments);
    };
    history.replaceState = function() {
        if (!interceptNav(arguments[2])) originalReplaceState.apply(this, arguments);
    };

    // 2. Intercept location.href assignment
    let currentHref = window.location.href;
    const hrefCheck = setInterval(() => {
        if (window.location.href !== currentHref) {
            const newPath = window.location.pathname;
            if (newPath === '/' || newPath === '' || newPath.includes('close')) {
                redirectToWelcome();
            }
            currentHref = window.location.href;
        }
    }, 200);

    // 3. Watch for Jitsi conference events via APP object
    const waitForApp = setInterval(() => {
        if (typeof APP !== 'undefined' && APP.conference) {
            clearInterval(waitForApp);
            // Hook into conference will leave
            if (APP.conference._location) {
                const origAssign = APP.conference._location.assign;
                if (origAssign) {
                    APP.conference._location.assign = function(url) {
                        redirectToWelcome();
                    };
                }
            }
            // Listen for hangup via APP
            const origHangup = APP.conference.hangup;
            if (origHangup) {
                APP.conference.hangup = function() {
                    origHangup.apply(this, arguments);
                    setTimeout(redirectToWelcome, 500);
                };
            }
        }
    }, 500);

    // 4. Watch for DOM changes indicating meeting ended
    const observer = new MutationObserver(() => {
        // Jitsi close/feedback/thankyou page
        const closePage = document.querySelector(
            '[class*="close-page"], [class*="meetingEnded"], [class*="location-changed"], ' +
            '[class*="thank-you"], [data-testid*="close"], [class*="meeting-ended"]'
        );
        if (closePage) redirectToWelcome();

        // Toolbar disappeared = conference ended
        const toolbox = document.getElementById('new-toolbox');
        const conferenceEl = document.querySelector('[id*="largeVideo"]');
        if (conferenceEl && toolbox && toolbox.style.display === 'none' &&
            !document.querySelector('.premeeting-screen')) {
            setTimeout(redirectToWelcome, 300);
        }
    });

    if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true, attributes: true });
    } else {
        document.addEventListener('DOMContentLoaded', () => {
            observer.observe(document.body, { childList: true, subtree: true, attributes: true });
        });
    }

    // 5. Handle popstate (back button after leaving)
    window.addEventListener('popstate', () => {
        const path = window.location.pathname;
        if (path === '/' || path === '') redirectToWelcome();
    });

    // 6. Handle beforeunload cleanup
    window.addEventListener('unload', () => {
        clearInterval(hrefCheck);
        clearInterval(waitForApp);
        observer.disconnect();
    });

    // Expose for external use
    window.LearnXMeeting = { leaveMeeting: redirectToWelcome };
})();
