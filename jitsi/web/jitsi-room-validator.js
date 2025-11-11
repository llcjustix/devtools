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

    // Get JWT token from browser storage
    const getJwtToken = () => {
        // Try sessionStorage first (single tab), then localStorage (persistent across tabs)
        return sessionStorage.getItem('jitsi_jwt_token') || localStorage.getItem('jitsi_jwt_token');
    };

    // Validate user access for private meetings (browser-specific endpoint)
    const validateUserAccess = (roomName, jwtToken) => {
        return fetch(`${meetingServiceUrl}/webhooks/jitsi/validate-browser-access`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${jwtToken}`  // Spring Security will validate token
            },
            body: JSON.stringify({
                roomName: roomName,
                userJid: 'browser@meet.jitsi',  // Browser validation
                timestamp: Date.now()
            })
        });
    };

    // Perform validation - must wait for body to exist
    const performValidation = () => {
        const overlay = showLoadingOverlay();

        // Step 1: Check room status (lightweight check)
        fetch(`${meetingServiceUrl}/webhooks/jitsi/check-room-status/${encodeURIComponent(roomName)}`)
            .then(response => {
                if (response.ok) {
                    // Meeting exists - get room info
                    return response.json().then(roomInfo => {
                        console.log('[Jitsi Room Validator] ✓ Room found:', roomInfo);
                        console.log(`  - Title: ${roomInfo.title}`);
                        console.log(`  - Status: ${roomInfo.status}`);
                        console.log(`  - Public: ${!roomInfo.requireAuth}`);

                        // If public meeting, allow access immediately
                        if (!roomInfo.requireAuth) {
                            console.log('[Jitsi Room Validator] ✓ Public meeting - access granted');
                            overlay.remove();
                            return;
                        }

                        // Private meeting - need to validate access
                        console.log('[Jitsi Room Validator] Private meeting - validating access...');

                        // Get JWT token from browser storage
                        const jwtToken = getJwtToken();

                        if (!jwtToken) {
                            // No token - redirect to login (on same Jitsi server)
                            console.log('[Jitsi Room Validator] No token found - redirecting to login');
                            const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                            window.location.href = redirectUrl;
                            return;
                        }

                        // Step 2: Validate user access with token
                        console.log('[Jitsi Room Validator] Validating access with token...');
                        validateUserAccess(roomName, jwtToken)
                            .then(validateResponse => {
                                if (validateResponse.ok) {
                                    return validateResponse.json().then(accessInfo => {
                                        console.log('[Jitsi Room Validator] Access validation response:', accessInfo);

                                        if (accessInfo.allowed) {
                                            console.log('[Jitsi Room Validator] ✓ Access granted');
                                            overlay.remove();
                                        } else if (accessInfo.requireAuth) {
                                            // Token invalid/expired - redirect to login (on same Jitsi server)
                                            console.log('[Jitsi Room Validator] Token invalid - redirecting to login');
                                            const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                                            window.location.href = redirectUrl;
                                        } else {
                                            // Access denied (not invited, etc.)
                                            console.log('[Jitsi Room Validator] ✗ Access denied:', accessInfo.reason);
                                            window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}&reason=${encodeURIComponent(accessInfo.reason || 'Not authorized')}`;
                                        }
                                    });
                                } else {
                                    throw new Error(`Access validation failed: ${validateResponse.status}`);
                                }
                            })
                            .catch(error => {
                                console.error('[Jitsi Room Validator] Access validation error:', error);
                                window.location.href = `/error.html?error=validation-error&room=${encodeURIComponent(roomName)}`;
                            });
                    });
                } else if (response.status === 404) {
                    // Meeting not found
                    console.log('[Jitsi Room Validator] ✗ Room not found');
                    window.location.href = `/error.html?error=meeting-not-found&room=${encodeURIComponent(roomName)}`;
                } else if (response.status === 403) {
                    // Forbidden - authenticated but not invited
                    return response.json().then(roomInfo => {
                        console.log('[Jitsi Room Validator] ✗ Access denied - not invited:', roomInfo);
                        window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}&title=${encodeURIComponent(roomInfo.title || '')}`;
                    }).catch(() => {
                        window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}`;
                    });
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
