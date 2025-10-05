/**
 * Jitsi Meet Room Configuration Plugin
 *
 * This plugin receives room configuration from Prosody via XMPP messages
 * and applies the settings to the Jitsi Meet interface.
 *
 * Installation:
 * 1. Copy this file to: /usr/share/jitsi-meet/libs/
 * 2. Add to Jitsi config.js:
 *    ```
 *    customToolbarButtons: [],
 *    customParticipantMenuButtons: [],
 *    ```
 * 3. Load this plugin in interface_config.js or via script tag in index.html
 *
 * The plugin listens for ROOM_CONFIG messages sent by Prosody when users join.
 * Configuration is sent via encrypted XMPP, not visible in URL parameters.
 */

(function() {
    'use strict';

    console.log('[RoomConfig] Plugin loading...');

    // Wait for Jitsi Meet API to be available
    function initPlugin() {
        if (typeof APP === 'undefined' || !APP.conference) {
            console.log('[RoomConfig] Waiting for Jitsi Meet API...');
            setTimeout(initPlugin, 500);
            return;
        }

        console.log('[RoomConfig] Jitsi Meet API available, initializing...');

        // Get XMPP connection
        const connection = APP.conference._room?.xmpp?.connection;

        if (!connection) {
            console.warn('[RoomConfig] No XMPP connection found, retrying...');
            setTimeout(initPlugin, 1000);
            return;
        }

        // Listen for ROOM_CONFIG messages from Prosody
        connection.addHandler(handleRoomConfig, 'http://jitsi.org/jitmeet', 'message', 'groupchat');
        console.log('[RoomConfig] Message handler registered');
    }

    /**
     * Handle ROOM_CONFIG message from Prosody
     */
    function handleRoomConfig(message) {
        try {
            // Parse JSON message
            const jsonElement = message.querySelector('json-message');
            if (!jsonElement) {
                return true; // Continue listening
            }

            const data = JSON.parse(jsonElement.textContent);

            if (data.type !== 'ROOM_CONFIG') {
                return true; // Not our message
            }

            console.log('[RoomConfig] Received configuration:', data.config);

            // Apply configuration
            applyConfiguration(data.config);

        } catch (error) {
            console.error('[RoomConfig] Error parsing message:', error);
        }

        return true; // Continue listening for more messages
    }

    /**
     * Apply room configuration to Jitsi interface
     */
    function applyConfiguration(config) {
        console.log('[RoomConfig] Applying configuration...');

        // Core features
        if (config.chatEnabled === false) {
            console.log('[RoomConfig] Disabling chat');
            APP.conference.muteLocalChatParticipant?.(true);
            disableToolbarButton('chat');
        }

        if (config.screenShareEnabled === false) {
            console.log('[RoomConfig] Disabling screen sharing');
            disableToolbarButton('desktop');
        }

        if (config.recordingEnabled === false) {
            console.log('[RoomConfig] Disabling recording');
            disableToolbarButton('recording');
        }

        if (config.whiteboardEnabled === false) {
            console.log('[RoomConfig] Disabling whiteboard');
            disableToolbarButton('whiteboard');
        }

        // Participant features
        if (config.reactionsEnabled === false) {
            console.log('[RoomConfig] Disabling reactions');
            disableToolbarButton('reactions');
        }

        if (config.raiseHandEnabled === false) {
            console.log('[RoomConfig] Disabling raise hand');
            disableToolbarButton('raisehand');
        }

        if (config.privateMessagesEnabled === false) {
            console.log('[RoomConfig] Disabling private messages');
            // TODO: Implement private message disabling
        }

        if (config.tileViewEnabled === false) {
            console.log('[RoomConfig] Disabling tile view');
            disableToolbarButton('tileview');
        }

        // Media features
        if (config.liveStreamingEnabled === false) {
            console.log('[RoomConfig] Disabling live streaming');
            disableToolbarButton('livestreaming');
        }

        if (config.virtualBackgroundsEnabled === false) {
            console.log('[RoomConfig] Disabling virtual backgrounds');
            disableToolbarButton('select-background');
        }

        if (config.noiseSuppressionEnabled === false) {
            console.log('[RoomConfig] Disabling noise suppression');
            disableToolbarButton('noisesuppression');
        }

        if (config.e2eeEnabled === true) {
            console.log('[RoomConfig] Enabling E2EE');
            enableToolbarButton('e2ee');
        }

        // Moderation features
        if (config.pollsEnabled === false) {
            console.log('[RoomConfig] Disabling polls');
            disableToolbarButton('polls');
        }

        if (config.breakoutRoomsEnabled === false) {
            console.log('[RoomConfig] Disabling breakout rooms');
            disableToolbarButton('breakout-rooms');
        }

        if (config.speakerStatsEnabled === false) {
            console.log('[RoomConfig] Disabling speaker stats');
            disableToolbarButton('stats');
        }

        if (config.securityEnabled === false) {
            console.log('[RoomConfig] Disabling security options');
            disableToolbarButton('security');
        }

        // UI features
        if (config.closedCaptionsEnabled === false) {
            console.log('[RoomConfig] Disabling closed captions');
            disableToolbarButton('closedcaptions');
        }

        if (config.sharedDocumentEnabled === false) {
            console.log('[RoomConfig] Disabling shared document');
            disableToolbarButton('shareaudio');
        }

        // Auto-mute/video settings
        if (config.muteOnJoin === true) {
            console.log('[RoomConfig] Auto-muting on join');
            APP.conference.muteAudio(true);
        }

        if (config.videoOffOnJoin === true) {
            console.log('[RoomConfig] Disabling video on join');
            APP.conference.muteVideo(true);
        }

        // Meeting info
        if (config.meetingTitle) {
            console.log('[RoomConfig] Setting meeting title:', config.meetingTitle);
            APP.conference.setSubject?.(config.meetingTitle);
        }

        console.log('[RoomConfig] Configuration applied successfully');
    }

    /**
     * Disable a toolbar button
     */
    function disableToolbarButton(buttonName) {
        try {
            const button = document.querySelector(`[data-testid="${buttonName}"]`) ||
                          document.querySelector(`.toolbar-button-with-badge[aria-label*="${buttonName}"]`);

            if (button) {
                button.style.display = 'none';
                button.disabled = true;
            }
        } catch (error) {
            console.warn(`[RoomConfig] Could not disable button: ${buttonName}`, error);
        }
    }

    /**
     * Enable a toolbar button
     */
    function enableToolbarButton(buttonName) {
        try {
            const button = document.querySelector(`[data-testid="${buttonName}"]`) ||
                          document.querySelector(`.toolbar-button-with-badge[aria-label*="${buttonName}"]`);

            if (button) {
                button.style.display = '';
                button.disabled = false;
            }
        } catch (error) {
            console.warn(`[RoomConfig] Could not enable button: ${buttonName}`, error);
        }
    }

    // Start plugin when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initPlugin);
    } else {
        initPlugin();
    }

    console.log('[RoomConfig] Plugin loaded');

})();
