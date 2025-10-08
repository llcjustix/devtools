-- Room Access Validator Module for JustIX Academy
-- Validates room access before allowing users to join
-- Flow:
--   1. User tries to join room (with or without JWT token)
--   2. Module calls meeting-service webhook to validate
--   3. Service checks: room exists, not expired, public/private, user permissions
--   4. If private and no JWT -> reject with auth_required (triggers login redirect)
--   5. If public or valid JWT -> allow join

local http = require "net.http"
local json = require "cjson"
local jid_bare = require "util.jid".bare
local jid_split = require "util.jid".split
local st = require "util.stanza"

local validate_url = module:get_option_string("validate_access_url", "http://meeting-service:2031/webhooks/jitsi/validate-access")
local webhook_secret = module:get_option_string("webhook_secret", "webhook-secret-change-in-production")

module:log("info", "Room Access Validator Module loaded")
module:log("info", "Validate URL: %s", validate_url)

-- Check if user has valid JWT token (authenticated user)
local function is_authenticated(user_jid)
    -- Users from auth.meet.jitsi domain are authenticated
    -- Users from guest.meet.jitsi domain are guests
    return user_jid and not user_jid:find("@guest%.")
end

-- Extract JWT token from session context
local function get_jwt_token(event)
    -- Check if the session has JWT context
    local session = event.origin
    if session and session.jitsi_meet_context_user then
        local context = session.jitsi_meet_context_user
        if context.token then
            return context.token
        end
    end
    return nil
end

-- Validate room access with meeting-service
local function validate_room_access(room_name, user_jid, has_jwt)
    local request_body = json.encode({
        roomName = room_name,
        userJid = user_jid,
        hasJWT = has_jwt,
        timestamp = os.time(),
        secret = webhook_secret
    })

    module:log("debug", "Validating access: room=%s, user=%s, hasJWT=%s",
        room_name, user_jid, tostring(has_jwt))

    -- Use http.request with callback (non-blocking)
    local response_received = false
    local validation_result = {
        allowed = false,
        reason = "timeout",
        requiresAuth = false,
        redirectUrl = nil
    }

    http.request(validate_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        body = request_body
    }, function(body, code, response)
        response_received = true

        if code == 200 and body then
            local ok, data = pcall(json.decode, body)
            if ok and data then
                validation_result.allowed = data.allowed == true
                validation_result.reason = data.reason or "unknown"
                validation_result.requiresAuth = data.requiresAuth == true
                validation_result.redirectUrl = data.redirectUrl
                validation_result.isPublic = data.isPublic == true
                validation_result.roomExists = data.roomExists ~= false
                validation_result.isExpired = data.isExpired == true

                module:log("info", "Validation response: allowed=%s, reason=%s, requiresAuth=%s, isPublic=%s",
                    tostring(validation_result.allowed),
                    tostring(validation_result.reason),
                    tostring(validation_result.requiresAuth),
                    tostring(validation_result.isPublic))
            else
                module:log("error", "Failed to parse validation response: %s", tostring(body))
                validation_result.reason = "parse_error"
            end
        else
            module:log("warn", "Validation request failed: code=%s", tostring(code))
            validation_result.reason = "service_unavailable"
        end
    end)

    -- Wait for response with timeout
    local timeout = 5 -- 5 seconds
    local start_time = os.time()
    while not response_received and (os.time() - start_time) < timeout do
        -- Small delay to prevent busy waiting
        os.execute("sleep 0.01")
    end

    if not response_received then
        module:log("error", "Validation request timed out for room: %s", room_name)
        -- Default behavior on timeout: allow if meeting-service is down (fail open)
        -- Change to false (fail closed) if you want to block on service failure
        validation_result.allowed = false
        validation_result.reason = "service_timeout"
    end

    return validation_result
end

-- Hook into MUC occupant pre-join to validate access
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local stanza = event.stanza

    if not room or not occupant then
        module:log("debug", "Skipping validation: missing room or occupant")
        return nil -- Allow (shouldn't happen)
    end

    local room_jid = room.jid
    local room_name = jid_split(room_jid)
    local user_jid = occupant.bare_jid

    -- Check if user is authenticated (has JWT)
    local has_jwt = is_authenticated(user_jid)

    module:log("info", "Checking access: room=%s, user=%s, authenticated=%s",
        room_name, user_jid, tostring(has_jwt))

    -- Validate with meeting-service
    local result = validate_room_access(room_name, user_jid, has_jwt)

    if result.allowed then
        module:log("info", "✓ Access GRANTED: room=%s, user=%s", room_name, user_jid)
        return nil -- Allow join
    end

    -- Access denied - determine error type
    module:log("warn", "✗ Access DENIED: room=%s, user=%s, reason=%s",
        room_name, user_jid, result.reason)

    local error_type, error_condition, error_text

    if result.requiresAuth or (not result.isPublic and not has_jwt) then
        -- Private room, no JWT -> redirect to login
        error_type = "auth"
        error_condition = "not-authorized"
        error_text = "This is a private meeting. Please log in to join."

        -- Add redirect URL if provided by service
        if result.redirectUrl then
            module:log("info", "Redirecting to: %s", result.redirectUrl)
        end

    elseif result.isExpired then
        error_type = "cancel"
        error_condition = "gone"
        error_text = "This meeting has expired."

    elseif not result.roomExists then
        error_type = "cancel"
        error_condition = "item-not-found"
        error_text = "Meeting not found."

    else
        -- Generic access denied
        error_type = "auth"
        error_condition = "forbidden"
        error_text = result.reason or "You are not authorized to join this meeting."
    end

    -- Send error stanza to client
    local reply = st.error_reply(stanza, error_type, error_condition, error_text)

    -- Add custom redirect URL element if available
    if result.redirectUrl then
        reply:tag("redirect", { xmlns = "urn:xmpp:jitsi:redirect" })
            :text(result.redirectUrl):up()
    end

    event.origin.send(reply)

    return true -- Block the join
end, 10) -- Priority 10 to run early

module:log("info", "Room Access Validator Module initialized")
