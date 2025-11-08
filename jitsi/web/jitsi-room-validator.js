/**
 * Jitsi Room Validator - Pre-validation before loading Jitsi Meet
 *
 * This script intercepts Jitsi's initialization and validates the room exists
 * in the backend before allowing the conference to proceed.
 */

(function() {
    'use strict';

    console.log('[Jitsi Room Validator] Initializing room validation...');

    // Get room name from URL (same way Jitsi does)
    const getRoomName = () => {
        const path = window.location.pathname;
        // Remove leading slash and any trailing slashes
        return path.substring(1).replace(/\/+$/, '');
    };

    // Meeting service URL detection
    const getMeetingServiceUrl = () => {
        if (window.MEETING_SERVICE_URL) {
            return window.MEETING_SERVICE_URL;
        }
        const hostname = window.location.hostname;
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            return 'http://localhost:2031';
        }
        if (hostname === 'host.docker.internal') {
            return 'http://host.docker.internal:2031';
        }
        const protocol = window.location.protocol;
        return `${protocol}//${hostname.replace('meet.', '')}`;
    };

    const roomName = getRoomName();

    // Skip validation for root path or static resources
    if (!roomName || roomName === '' || roomName.includes('.')) {
        console.log('[Jitsi Room Validator] Skipping validation for:', roomName);
        return;
    }

    console.log('[Jitsi Room Validator] Validating room:', roomName);

    const meetingServiceUrl = getMeetingServiceUrl();
    console.log('[Jitsi Room Validator] Meeting service URL:', meetingServiceUrl);

    // Show loading overlay
    const showLoadingOverlay = () => {
        const overlay = document.createElement('div');
        overlay.id = 'room-validation-overlay';
        overlay.innerHTML = `
            <style>
                #room-validation-overlay {
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    background: linear-gradient(135deg, #2A3A4B 0%, #1a242f 100%);
                    z-index: 999999;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .validation-loader {
                    text-align: center;
                    color: white;
                }
                .validation-spinner {
                    border: 4px solid rgba(255, 255, 255, 0.1);
                    border-left-color: #5DADE2;
                    border-radius: 50%;
                    width: 50px;
                    height: 50px;
                    animation: validation-spin 1s linear infinite;
                    margin: 0 auto 20px;
                }
                @keyframes validation-spin {
                    to { transform: rotate(360deg); }
                }
            </style>
            <div class="validation-loader">
                <div class="validation-spinner"></div>
                <p>Validating meeting access...</p>
            </div>
        `;
        document.body.appendChild(overlay);
        return overlay;
    };

    // Perform validation - must wait for body to exist
    const performValidation = () => {
        const overlay = showLoadingOverlay();

        // Check room status with backend
        fetch(`${meetingServiceUrl}/webhooks/jitsi/check-room-status/${encodeURIComponent(roomName)}`)
            .then(response => {
                if (response.ok) {
                    // Meeting exists and is active - get room info
                    return response.json().then(roomInfo => {
                        console.log('[Jitsi Room Validator] ✓ Room validated successfully:', roomInfo);
                        console.log(`  - Title: ${roomInfo.title}`);
                        console.log(`  - Status: ${roomInfo.status}`);
                        overlay.remove();
                    });
                } else if (response.status === 404) {
                    // Meeting not found
                    console.log('[Jitsi Room Validator] ✗ Room not found');
                    window.location.href = `/error.html?error=meeting-not-found&room=${encodeURIComponent(roomName)}`;
                } else if (response.status === 410) {
                    // Meeting ended - try to get status info
                    return response.json().then(roomInfo => {
                        console.log('[Jitsi Room Validator] ✗ Meeting ended:', roomInfo);
                        window.location.href = `/error.html?error=meeting-ended&room=${encodeURIComponent(roomName)}&title=${encodeURIComponent(roomInfo.title || '')}`;
                    }).catch(() => {
                        window.location.href = `/error.html?error=meeting-ended&room=${encodeURIComponent(roomName)}`;
                    });
                } else {
                    // Other error
                    console.log('[Jitsi Room Validator] ✗ Validation failed:', response.status);
                    window.location.href = `/error.html?error=service-error&room=${encodeURIComponent(roomName)}`;
                }
            })
            .catch(error => {
                console.error('[Jitsi Room Validator] ✗ Validation error:', error);
                window.location.href = `/error.html?error=service-error&reason=${encodeURIComponent(error.message)}&room=${encodeURIComponent(roomName)}`;
            });
    };

    // Wait for DOM to be ready before showing overlay
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', performValidation);
    } else {
        // DOM already loaded
        performValidation();
    }

})();
