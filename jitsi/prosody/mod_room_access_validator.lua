-- Room Access Validator Module
-- Checks with meeting-service via /validate-access endpoint before allowing users to join rooms
-- Uses single domain approach - no separate guest/auth domains

local http = require "net.http"
local json = require "util.json"
local jid_bare = require "util.jid".bare
local jid_split = require "util.jid".split

local validate_url = module:get_option_string("validate_access_url", "http://meeting-service:2031/webhooks/jitsi/validate-access")
local webhook_secret = module:get_option_string("webhook_secret", "webhook-secret-change-in-production")

module:log("info", "Room Access Validator Module loaded")
module:log("info", "Validate URL: %s", validate_url)

-- Extract JWT token from stanza if present
local function extract_jwt_token(stanza)
    -- JWT token should be in the presence stanza as a custom element
    local jwt_elem = stanza:get_child("jwt", "urn:xmpp:jitsi:jwt")
    if jwt_elem then
        return jwt_elem:get_text()
    end
    return nil
end

-- Make HTTP request to validate access
local function validate_access_with_service(room_name, user_jid, jwt_token, meeting_id)
    local request_body = json.encode({
        roomName = room_name,
        userJid = user_jid,
        meetingId = meeting_id,
        timestamp = os.time(),
        secret = webhook_secret
    })

    module:log("debug", "Validating access: room=%s, user=%s", room_name, user_jid)

    local response_text = nil
    local response_code = nil
    local wait, done = async.waiter()

    http.request(validate_url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body),
            ["Authorization"] = jwt_token and ("Bearer " .. jwt_token) or ""
        },
        body = request_body
    }, function(body, code)
        response_text = body
        response_code = code
        done()
    end)

    wait()

    if response_code ~= 200 then
        module:log("warn", "Access validation failed: room=%s, user=%s, code=%s",
            room_name, user_jid, tostring(response_code))
        return false, "access_denied"
    end

    local ok, response_data = pcall(json.decode, response_text)
    if not ok or not response_data then
        module:log("error", "Failed to parse validation response: %s", tostring(response_text))
        return false, "service_error"
    end

    module:log("info", "Access validation result: room=%s, user=%s, allowed=%s",
        room_name, user_jid, tostring(response_data.allowed or false))

    return response_data.allowed == true, response_data.reason
end

-- Hook into MUC occupant pre-join
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local stanza = event.stanza

    if not room or not occupant then
        return nil
    end

    local room_jid = room.jid
    local room_name = jid_split(room_jid)
    local user_jid = occupant.bare_jid

    -- Extract meeting ID from room name if present (format: roomname@conferenc or just roomname)
    local meeting_id = room_name

    -- Extract JWT token from stanza
    local jwt_token = extract_jwt_token(stanza)

    module:log("debug", "Pre-join check: room=%s, user=%s, has_token=%s",
        room_name, user_jid, tostring(jwt_token ~= nil))

    -- Call validation service
    local allowed, reason = validate_access_with_service(room_name, user_jid, jwt_token, meeting_id)

    if not allowed then
        module:log("info", "Access DENIED: room=%s, user=%s, reason=%s",
            room_name, user_jid, tostring(reason))

        -- Return error to prevent join
        local reply = st.error_reply(stanza, "auth", "forbidden",
            "You are not authorized to join this room: " .. (reason or "access_denied"))
        event.origin.send(reply)
        return true -- Block the join
    end

    module:log("info", "Access GRANTED: room=%s, user=%s", room_name, user_jid)
    return nil -- Allow the join
end, 10) -- Priority 10 to run before other hooks

module:log("info", "Room Access Validator Module initialized")
