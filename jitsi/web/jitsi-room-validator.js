/**
 * Jitsi Room Validator - Pre-validation before loading Jitsi Meet
 *
 * This script intercepts Jitsi's initialization and validates the room exists
 * in the backend before allowing the conference to proceed.
 */

(function() {
    'use strict';

    console.log('[LearnX Room Validator] Initializing room validation...');

    // Token storage key names (configurable via window env)
    const TOKEN_KEY = window.LEARNX_TOKEN_KEY || 'learnx_access_token';
    const REFRESH_KEY = window.LEARNX_REFRESH_KEY || 'learnx_refresh_token';

    // Get room name from URL (same way Jitsi does)
    const getRoomName = () => {
        const path = window.location.pathname;
        const name = path.substring(1).replace(/\/+$/, '');
        // Validate room name: only alphanumeric, hyphens, underscores
        if (name && !/^[a-zA-Z0-9_-]+$/.test(name)) return null;
        return name;
    };

    // Service URL detection (via API gateway)
    const getGatewayBase = () => {
        const hostname = window.location.hostname;
        return `${window.location.protocol}//${hostname.replace('meet.', '')}`;
    };
    const getMeetingServiceUrl = () => {
        if (window.MEETING_SERVICE_URL) return window.MEETING_SERVICE_URL;
        return getGatewayBase() + '/meeting-service';
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
        return sessionStorage.getItem(TOKEN_KEY) || localStorage.getItem(TOKEN_KEY);
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
        sessionStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(TOKEN_KEY);
        sessionStorage.removeItem(REFRESH_KEY);
        localStorage.removeItem(REFRESH_KEY);
    };

    // Get refresh token
    const getRefreshToken = () => {
        return sessionStorage.getItem(REFRESH_KEY) || localStorage.getItem(REFRESH_KEY);
    };

    // Auth service URL detection (via API gateway)
    const getAuthServiceUrl = () => {
        if (window.AUTH_SERVICE_URL) return window.AUTH_SERVICE_URL;
        return getGatewayBase() + '/auth-service';
    };

    // Try to refresh the access token
    const tryRefreshToken = async () => {
        const refreshToken = getRefreshToken();
        if (!refreshToken) return null;
        try {
            const resp = await fetch(`${getAuthServiceUrl()}/auth/token/refresh`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refreshToken })
            });
            if (resp.ok) {
                const data = await resp.json();
                if (data.access_token) {
                    sessionStorage.setItem(TOKEN_KEY, data.access_token);
                    localStorage.setItem(TOKEN_KEY, data.access_token);
                    if (data.refresh_token) {
                        sessionStorage.setItem(REFRESH_KEY, data.refresh_token);
                        localStorage.setItem(REFRESH_KEY, data.refresh_token);
                    }
                    return data.access_token;
                }
            }
        } catch (e) { console.log('[LearnX Room Validator] Token refresh failed:', e); }
        return null;
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

    // Validate user access with token (extracted for reuse after refresh)
    const proceedWithValidation = (jwtToken, roomName, overlay) => {
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
                            console.log('[LearnX Room Validator] Token invalid - redirecting to login');
                            window.location.href = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                        } else {
                            console.log('[LearnX Room Validator] ✗ Access denied:', accessInfo.reason);
                            window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}&reason=${encodeURIComponent(accessInfo.reason || 'Not authorized')}`;
                        }
                    });
                } else if (validateResponse.status === 401 || validateResponse.status === 403) {
                    // Token rejected — try refresh once
                    console.log('[LearnX Room Validator] Server rejected token (', validateResponse.status, ') - attempting refresh...');
                    return tryRefreshToken().then(newToken => {
                        if (newToken) {
                            return validateUserAccess(roomName, newToken).then(retryResp => {
                                if (retryResp.ok) {
                                    return retryResp.json().then(accessInfo => {
                                        if (accessInfo.allowed) { overlay.remove(); }
                                        else { window.location.href = `/error.html?error=access-denied&room=${encodeURIComponent(roomName)}`; }
                                    });
                                }
                                clearToken();
                                window.location.href = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                            });
                        }
                        clearToken();
                        window.location.href = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                    });
                } else {
                    throw new Error(`Access validation failed: ${validateResponse.status}`);
                }
            })
            .catch(error => {
                console.error('[LearnX Room Validator] Access validation error:', error);
                window.location.href = `/error.html?error=validation-error&room=${encodeURIComponent(roomName)}`;
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

                        // Check if token exists and is not expired; try refresh if expired
                        if (jwtToken && isTokenExpired(jwtToken)) {
                            console.log('[LearnX Room Validator] Token expired - attempting refresh...');
                            return tryRefreshToken().then(newToken => {
                                if (newToken) {
                                    console.log('[LearnX Room Validator] Token refreshed successfully');
                                    proceedWithValidation(newToken, roomName, overlay);
                                } else {
                                    clearToken();
                                    console.log('[LearnX Room Validator] Refresh failed - redirecting to login');
                                    window.location.href = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                                }
                            });
                        }

                        if (!jwtToken) {
                            // No token - redirect to login
                            console.log('[LearnX Room Validator] No valid token - redirecting to login');
                            const redirectUrl = `/login.html?room=${roomName}&returnUrl=${window.location.origin}/${roomName}`;
                            window.location.href = redirectUrl;
                            return;
                        }

                        proceedWithValidation(jwtToken, roomName, overlay);
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
                window.location.href = `/error.html?error=service-error&room=${encodeURIComponent(roomName)}`;
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
