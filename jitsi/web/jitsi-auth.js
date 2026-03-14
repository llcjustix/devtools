/**
 * Jitsi Authentication Integration - Using Keycloak from Auth-Service
 *
 * This script ensures users are authenticated via Keycloak before joining private Jitsi meetings.
 * The existing Keycloak authentication (via Spring Security OAuth2) is used directly.
 *
 * Flow:
 * 1. User accesses: https://meet.learnx.uz/room-abc
 * 2. For PRIVATE meetings: redirect to login if not authenticated
 * 3. For PUBLIC meetings: allow anonymous access
 * 4. Spring Security handles Keycloak authentication
 * 5. JWT stored in sessionStorage/localStorage
 * 6. Prosody validates access via meeting-service webhook
 *
 * Note: Authentication happens on-demand when Prosody validates room access.
 * No pre-flight auth check needed - Spring Security + Prosody handle it.
 */

(function() {
    'use strict';

    // Get meeting service URL (via API gateway)
    const meetingServiceUrl = (() => {
        if (window.MEETING_SERVICE_URL) return window.MEETING_SERVICE_URL;
        const base = `${window.location.protocol}//${window.location.hostname.replace('meet.', '')}`;
        return base + '/meeting-service';
    })();

    /**
     * Authentication is handled by Spring Security + Prosody.
     * No pre-flight check needed - Prosody will validate when user tries to join.
     *
     * For private meetings:
     * - Prosody calls meeting-service /validate-access webhook
     * - If not authenticated → returns requireAuth: true
     * - User sees "Please log in" error in Jitsi
     * - This script can optionally redirect to login proactively (for better UX)
     */
    function isPrivateMeeting() {
        // We don't know if meeting is private until Prosody validates
        // For better UX, we could call meeting-service to check
        // But for now, let Prosody handle it (simpler)
        return false; // Assume public for now
    }

    /**
     * Redirect to login page (Spring Security OAuth2 login)
     */
    function redirectToLogin() {
        const currentUrl = window.location.href;

        // Construct login URL - Spring Security will handle Keycloak redirect
        // After login, user will be redirected back to this page
        const loginUrl = `${meetingServiceUrl}/oauth2/authorization/keycloak`;

        console.log('[LearnX Meets] Redirecting to login...');
        console.log('[LearnX Meets] Current URL:', currentUrl);
        console.log('[LearnX Meets] Login URL:', loginUrl);

        // Store current URL to return after login
        try {
            sessionStorage.setItem('learnx_return_url', currentUrl);
        } catch (e) {
            console.warn('[LearnX Meets] Could not store return URL:', e);
        }

        // Redirect to Spring Security login endpoint
        window.location.href = loginUrl;
    }

    /**
     * Handle connection errors from Jitsi
     */
    function handleConnectionError(error) {
        console.log('[LearnX Meets] Connection error:', error);

        // Extract room name from URL
        const roomName = window.location.pathname.substring(1);

        // Map error codes to friendly error pages
        const errorMappings = {
            'item-not-found': { error: 'meeting-not-found', reason: 'The meeting does not exist in our system' },
            'gone': { error: 'meeting-ended', reason: 'The meeting has ended or been cancelled' },
            'not-allowed': { error: 'unauthorized', reason: 'You need to log in to join this private meeting' },
            'forbidden': { error: 'unauthorized', reason: 'You are not authorized to join this meeting' },
            'service-unavailable': { error: 'service-error', reason: 'The meeting service is temporarily unavailable' }
        };

        let errorType = 'meeting-not-found';
        let errorReason = 'Unknown error';

        // Check if error contains condition
        if (error && error.name && errorMappings[error.name]) {
            errorType = errorMappings[error.name].error;
            errorReason = errorMappings[error.name].reason;
        } else if (error && error.message) {
            errorReason = error.message;
        }

        // Redirect to error page
        const errorUrl = `/error.html?error=${errorType}&reason=${encodeURIComponent(errorReason)}&room=${encodeURIComponent(roomName)}`;
        console.log('[LearnX Meets] Redirecting to error page:', errorUrl);
        window.location.href = errorUrl;
    }

    /**
     * Initialize authentication (currently passive - Prosody handles validation)
     */
    function initAuth() {
        console.log('[LearnX Meets] Authentication integration loaded');
        console.log('[LearnX Meets] Spring Security session will be validated by Prosody');
        console.log('[LearnX Meets] For private meetings: login required');
        console.log('[LearnX Meets] For public meetings: anonymous access allowed');

        // Listen for Jitsi conference errors
        if (window.APP) {
            window.APP.conference.addListener(window.JitsiMeetJS.events.conference.CONFERENCE_FAILED, (error) => {
                handleConnectionError(error);
            });
        }

        // Listen for connection errors (fallback)
        window.addEventListener('jitsi-connection-failed', (event) => {
            handleConnectionError(event.detail);
        });
    }

    /**
     * Show authentication message to user
     */
    function showAuthMessage(message) {
        // Create overlay
        const overlay = document.createElement('div');
        overlay.id = 'jitsi-auth-overlay';
        overlay.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.8);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 10000;
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
        `;

        // Create message box
        const messageBox = document.createElement('div');
        messageBox.style.cssText = `
            background: #1a1a1a;
            padding: 40px;
            border-radius: 8px;
            text-align: center;
            max-width: 400px;
        `;

        const h2 = document.createElement('h2');
        h2.style.cssText = 'margin: 0 0 20px 0; font-size: 24px;';
        h2.textContent = 'Authentication Required';
        const p = document.createElement('p');
        p.style.cssText = 'margin: 0; font-size: 16px; color: #ccc;';
        p.textContent = message;
        messageBox.appendChild(h2);
        messageBox.appendChild(p);

        overlay.appendChild(messageBox);
        document.body.appendChild(overlay);
    }

    /**
     * Export functions for global access
     */
    window.JitsiAuth = {
        redirectToLogin: redirectToLogin
    };

    // Initialize
    initAuth();
})();
