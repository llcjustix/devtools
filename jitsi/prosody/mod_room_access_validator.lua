-- Room Access Validator Module for JustIX Academy
-- Validates room access before allowing users to join
--
-- Flow:
--   1. User tries to join room (with or without JWT token)
--   2. Module extracts JWT from Jitsi session context
--   3. Calls meeting-service webhook with JWT in Authorization header
--   4. Service validates: room exists, not expired, public/private, user permissions
--   5. If private and no JWT -> reject with auth_required (triggers login redirect)
--   6. If public or valid JWT -> allow join
--
-- Features:
--   - JWT token extraction from session (multiple fallback methods)
--   - HMAC-SHA256 signature for webhook authentication
--   - MeetingId extraction for faster database lookups
--   - Configurable via environment variables (MEETING_SERVICE_URL, JITSI_WEBHOOK_SECRET)

local http = require "socket.http"
local https = require "ssl.https"
local ltn12 = require "ltn12"
local json = require "cjson"
local jid_split = require "util.jid".split
local st = require "util.stanza"
local hmac_sha256 = require "util.hashes".hmac_sha256
local b64_encode = require "util.encodings".base64.encode

-- Get configuration from environment variables or Prosody config
local meeting_service_url = os.getenv("MEETING_SERVICE_URL") or module:get_option_string("meeting_service_url", "http://localhost:2031")
local validate_url = meeting_service_url .. "/webhooks/jitsi/validate-access"
local webhook_secret = os.getenv("JITSI_WEBHOOK_SECRET") or module:get_option_string("webhook_secret", "")

module:log("info", "Room Access Validator Module loaded")
module:log("info", "Meeting service URL: %s", validate_url)

-- Compute HMAC-SHA256 signature for webhook authentication
local function compute_hmac_signature(payload, secret)
    local signature = hmac_sha256(payload, secret, true) -- true = return binary
    return b64_encode(signature)
end

-- Extract JWT token from Jitsi session context
-- Jitsi stores JWT in session.jitsi_meet_context_user.token after authentication
local function get_jwt_token(session)
    if not session then
        return nil
    end

    -- Method 1: Check jitsi_meet_context_user (standard Jitsi JWT storage)
    if session.jitsi_meet_context_user and session.jitsi_meet_context_user.token then
        module:log("debug", "JWT found in jitsi_meet_context_user")
        return session.jitsi_meet_context_user.token
    end

    -- Method 2: Check auth_token (alternative storage)
    if session.auth_token then
        module:log("debug", "JWT found in auth_token")
        return session.auth_token
    end

    -- Method 3: Check custom storage (for URL parameter JWT)
    if session.jitsi_jwt then
        module:log("debug", "JWT found in jitsi_jwt")
        return session.jitsi_jwt
    end

    module:log("debug", "No JWT token found in session")
    return nil
end

-- Extract meetingId from room metadata (set by room-created webhook response)
local function get_meeting_id(room)
    if not room then
        return nil
    end

    -- Check if backend config was stored by mod_jitsi_webhooks_enhanced
    if room._data and room._data.backend_config then
        return room._data.backend_config.meetingId
    end

    return nil
end

-- Validate room access with meeting-service
local function validate_room_access(room, room_name, user_jid, jwt_token)
    local meeting_id = get_meeting_id(room)

    local request_payload = {
        roomName = room_name,
        meetingId = meeting_id,
        userJid = user_jid,
        timestamp = os.time()
    }

    local request_body = json.encode(request_payload)
    local signature = compute_hmac_signature(request_body, webhook_secret)

    local headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#request_body),
        ["X-Webhook-Signature"] = signature
    }

    -- Add JWT in Authorization header if present
    if jwt_token then
        headers["Authorization"] = "Bearer " .. jwt_token
        module:log("debug", "Sending JWT in Authorization header (length: %d)", #jwt_token)
    else
        module:log("debug", "No JWT token available - sending unauthenticated request")
    end

    module:log("debug", "Validating access: room=%s, meetingId=%s, user=%s, hasJWT=%s",
        room_name, tostring(meeting_id), user_jid, tostring(jwt_token ~= nil))

    -- Use synchronous HTTP request
    local validation_result = {
        allowed = false,
        reason = "unknown_error",
        requireAuth = false,
        redirectUrl = nil
    }

    -- Capture response body
    local response_chunks = {}

    -- Make synchronous HTTP POST request
    local body, code, response_headers, status_line = http.request{
        url = validate_url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_chunks)
    }

    local response_body = table.concat(response_chunks)

    module:log("debug", "HTTP response: code=%s, body_length=%d",
        tostring(code), #response_body)

    if code == 200 and response_body and #response_body > 0 then
        local ok, data = pcall(json.decode, response_body)
        if ok and data then
            validation_result.allowed = data.allowed == true
            validation_result.reason = data.reason or "unknown"
            validation_result.requireAuth = data.requireAuth == true
            validation_result.redirectUrl = data.redirectUrl
            validation_result.meetingTitle = data.meetingTitle
            validation_result.status = data.status
            validation_result.remainingMinutes = data.remainingMinutes

            -- Store room configuration for mod_jitsi_webhooks_enhanced to apply
            if data.configuration then
                room._data.backend_config = data.configuration
                module:log("info", "Stored room configuration: meetingId=%s", tostring(data.configuration.meetingId))
            end

            module:log("info", "Validation response: allowed=%s, reason=%s, requireAuth=%s, status=%s",
                tostring(validation_result.allowed),
                tostring(validation_result.reason),
                tostring(validation_result.requireAuth),
                tostring(validation_result.status))
        else
            module:log("error", "Failed to parse validation response: %s", tostring(response_body))
            validation_result.reason = "parse_error"
        end
    elseif code == 401 then
        module:log("warn", "Webhook authentication failed (invalid signature)")
        validation_result.reason = "webhook_auth_failed"
    elseif code then
        module:log("warn", "Validation request failed: code=%s", tostring(code))
        validation_result.reason = "service_unavailable"
    else
        module:log("error", "Validation request failed: no response code")
        validation_result.reason = "service_timeout"
    end

    return validation_result
end

-- Hook into MUC occupant pre-join to validate access
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local stanza = event.stanza
    local session = event.origin

    if not room or not occupant then
        module:log("debug", "Skipping validation: missing room or occupant")
        return nil -- Allow (shouldn't happen)
    end

    local room_jid = room.jid
    local room_name = jid_split(room_jid)
    local user_jid = occupant.bare_jid

    -- CRITICAL: Disable members_only BEFORE validation to prevent password prompt
    -- We handle authentication via JWT validation, not Prosody's built-in password system
    if not room._data.members_only_disabled then
        room:set_members_only(false)
        room:set_password(nil)
        room._data.members_only_disabled = true
        module:log("info", "Disabled members_only and password for room %s", room_name)
    end

    -- Extract JWT token from session
    local jwt_token = get_jwt_token(session)

    module:log("info", "Checking access: room=%s, user=%s, hasJWT=%s",
        room_name, user_jid, tostring(jwt_token ~= nil))

    -- Validate with meeting-service
    local result = validate_room_access(room, room_name, user_jid, jwt_token)

    if result.allowed then
        module:log("info", "✓ Access GRANTED: room=%s, user=%s", room_name, user_jid)

        -- Show remaining time warning if meeting is expiring soon
        if result.remainingMinutes and result.remainingMinutes <= 10 then
            module:log("warn", "Meeting %s expires in %d minutes", room_name, result.remainingMinutes)
        end

        return nil -- Allow join
    end

    -- Access denied - determine error type
    module:log("warn", "✗ Access DENIED: room=%s, user=%s, reason=%s",
        room_name, user_jid, result.reason)

    local error_type, error_condition, error_text

    if result.requireAuth and not jwt_token then
        -- Private meeting, no JWT -> redirect to login
        -- Use "cancel" type instead of "auth" to prevent Jitsi's password dialog
        error_type = "cancel"
        error_condition = "not-allowed"
        error_text = "This is a private meeting. Please log in to join. You will be redirected to the login page."

        -- Build login redirect URL
        local login_url = result.redirectUrl or ("https://learnx.uz/login?redirect=" .. room_name)
        module:log("info", "Redirecting to login: %s", login_url)

    elseif result.status == "CANCELLED" then
        error_type = "cancel"
        error_condition = "gone"
        error_text = "This meeting has been cancelled."

    elseif result.status == "COMPLETED" then
        error_type = "cancel"
        error_condition = "gone"
        error_text = "This meeting has ended."

    elseif result.reason == "Meeting duration has expired" then
        error_type = "cancel"
        error_condition = "gone"
        error_text = "This meeting has exceeded its time limit."

    elseif result.reason == "Meeting not found" then
        error_type = "cancel"
        error_condition = "item-not-found"
        error_text = "Meeting not found. Please check your link."

    elseif result.reason == "You are not invited to this meeting" then
        error_type = "auth"
        error_condition = "forbidden"
        error_text = "You are not invited to this meeting."

    elseif result.reason == "service_timeout" or result.reason == "service_unavailable" then
        error_type = "wait"
        error_condition = "service-unavailable"
        error_text = "Meeting service is temporarily unavailable. Please try again."

    else
        -- Generic access denied
        error_type = "auth"
        error_condition = "forbidden"
        error_text = result.reason or "You are not authorized to join this meeting."
    end

    -- Send error stanza to client
    local reply = st.error_reply(stanza, error_type, error_condition, error_text)

    -- Add custom redirect URL element if available (for Jitsi client to handle)
    if result.redirectUrl then
        reply:tag("redirect", { xmlns = "urn:xmpp:jitsi:redirect" })
            :text(result.redirectUrl):up()
    end

    event.origin.send(reply)

    return true -- Block the join
end, 10) -- Priority 10 to run early

module:log("info", "Room Access Validator Module initialized")
