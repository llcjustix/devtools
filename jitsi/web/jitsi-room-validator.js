/**
 * Jitsi Room Validator - Pre-validation before loading Jitsi Meet
 *
 * This script intercepts Jitsi's initialization and validates the room exists
 * in the backend before allowing the conference to proceed.
 */

(function() {
    'use strict';

    console.log('[LearnX Room Validator] Initializing room validation...');

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

    // Root path — redirect to welcome landing page
    if (!roomName || roomName === '') {
        console.log('[LearnX Room Validator] Root path - redirecting to welcome page');
        window.location.href = '/welcome.html';
        return;
    }

    // Skip validation for static resources
    if (roomName.includes('.')) {
        console.log('[LearnX Room Validator] Skipping validation for:', roomName);
        return;
    }

    console.log('[LearnX Room Validator] Validating room:', roomName);

    const meetingServiceUrl = getMeetingServiceUrl();
    console.log('[LearnX Room Validator] Meeting service URL:', meetingServiceUrl);

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
                    background: #faf8ff;
                    z-index: 999999;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                .validation-loader {
                    text-align: center;
                    color: #6b7280;
                }
                .validation-spinner {
                    border: 4px solid #f0ecf9;
                    border-left-color: #7c3aed;
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

    // Get JWT token from browser storage (sessionStorage → localStorage fallback)
    const getJwtToken = () => {
        return sessionStorage.getItem('jitsi_jwt_token') || localStorage.getItem('jitsi_jwt_token');
    };

    // Parse JWT payload
    const parseJwt = (token) => {
        try {
            const base64 = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
            return JSON.parse(atob(base64));
        } catch { return null; }
    };

    // Check if token is expired
    const isTokenExpired = (token) => {
        const payload = parseJwt(token);
        if (!payload || !payload.exp) return true;
        return (payload.exp * 1000) < Date.now();
    };

    // Clear stored tokens
    const clearToken = () => {
        sessionStorage.removeItem('jitsi_jwt_token');
        localStorage.removeItem('jitsi_jwt_token');
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
                        console.log('[LearnX Room Validator] ✓ Room found:', roomInfo);
                        console.log(`  - Title: ${roomInfo.title}`);
                        console.log(`  - Status: ${roomInfo.status}`);
                        console.log(`  - Public: ${!roomInfo.requireAuth}`);

                        // If public meeting, allow access immediately
                        if (!roomInfo.requireAuth) {
                            console.log('[LearnX Room Validator] ✓ Public meeting - access granted');
                            overlay.remove();
                            return;
                        }

                        // Private meeting - need to validate access
                        console.log('[LearnX Room Validator] Private meeting - validating access...');

                        // Get JWT token from browser storage
                        let jwtToken = getJwtToken();

                        // Check if token exists and is not expired
                        if (jwtToken && isTokenExpired(jwtToken)) {
                            console.log('[LearnX Room Validator] Token expired - clearing and redirecting to login');
                            clearToken();
                            jwtToken = null;
                        }

                        if (!jwtToken) {
                            // No token or expired - redirect to login
                            console.log('[LearnX Room Validator] No valid token - redirecting to login');
                            const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                            window.location.href = redirectUrl;
                            return;
                        }

                        // Step 2: Validate user access with token
                        console.log('[LearnX Room Validator] Validating access with token...');
                        validateUserAccess(roomName, jwtToken)
                            .then(validateResponse => {
                                if (validateResponse.ok) {
                                    return validateResponse.json().then(accessInfo => {
                                        console.log('[LearnX Room Validator] Access validation response:', accessInfo);

                                        if (accessInfo.allowed) {
                                            console.log('[LearnX Room Validator] ✓ Access granted');
                                            overlay.remove();
                                        } else if (accessInfo.requireAuth) {
                                            // Token invalid/expired - redirect to login (on same Jitsi server)
                                            console.log('[LearnX Room Validator] Token invalid - redirecting to login');
                                            const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                                            window.location.href = redirectUrl;
                                        } else {
                                            // Access denied (not invited, etc.)
                                            console.log('[LearnX Room Validator] ✗ Access denied:', accessInfo.reason);
                                            window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}&reason=${encodeURIComponent(accessInfo.reason || 'Not authorized')}`;
                                        }
                                    });
                                } else if (validateResponse.status === 401 || validateResponse.status === 403) {
                                    // Token rejected by server — clear and redirect to login
                                    console.log('[LearnX Room Validator] Server rejected token (', validateResponse.status, ') - redirecting to login');
                                    clearToken();
                                    const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                                    window.location.href = redirectUrl;
                                } else {
                                    throw new Error(`Access validation failed: ${validateResponse.status}`);
                                }
                            })
                            .catch(error => {
                                console.error('[LearnX Room Validator] Access validation error:', error);
                                window.location.href = `/error.html?error=validation-error&room=${encodeURIComponent(roomName)}`;
                            });
                    });
                } else if (response.status === 404) {
                    // Meeting not found
                    console.log('[LearnX Room Validator] ✗ Room not found');
                    window.location.href = `/error.html?error=meeting-not-found&room=${encodeURIComponent(roomName)}`;
                } else if (response.status === 403) {
                    // Forbidden - authenticated but not invited
                    return response.json().then(roomInfo => {
                        console.log('[LearnX Room Validator] ✗ Access denied - not invited:', roomInfo);
                        window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}&title=${encodeURIComponent(roomInfo.title || '')}`;
                    }).catch(() => {
                        window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}`;
                    });
                } else if (response.status === 410) {
                    // Meeting ended - try to get status info
                    return response.json().then(roomInfo => {
                        console.log('[LearnX Room Validator] ✗ Meeting ended:', roomInfo);
                        window.location.href = `/error.html?error=meeting-ended&room=${encodeURIComponent(roomName)}&title=${encodeURIComponent(roomInfo.title || '')}`;
                    }).catch(() => {
                        window.location.href = `/error.html?error=meeting-ended&room=${encodeURIComponent(roomName)}`;
                    });
                } else {
                    // Other error
                    console.log('[LearnX Room Validator] ✗ Validation failed:', response.status);
                    window.location.href = `/error.html?error=service-error&room=${encodeURIComponent(roomName)}`;
                }
            })
            .catch(error => {
                console.error('[LearnX Room Validator] ✗ Validation error:', error);
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
