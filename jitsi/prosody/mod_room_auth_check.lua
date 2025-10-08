-- Room-based authentication check module
-- Checks with meeting-service to determine if room requires authentication

local http = require "net.http"
local json = require "cjson"
local jid = require "util.jid"

local meeting_service_url = os.getenv("JITSI_WEBHOOK_URL") or "http://meeting-service:2031/webhooks/jitsi"
local webhook_secret = os.getenv("JITSI_WEBHOOK_SECRET") or ""

-- Cache for room access types (public/private)
local room_cache = {}
local cache_ttl = 300 -- 5 minutes

module:log("info", "Room Auth Check Module loaded")
module:log("info", "Meeting service URL: %s", meeting_service_url)

-- Function to check if room is public or private
local function check_room_access(room_name)
    -- Check cache first
    local cached = room_cache[room_name]
    if cached and (os.time() - cached.timestamp) < cache_ttl then
        module:log("debug", "Cache hit for room: %s, is_public: %s", room_name, tostring(cached.is_public))
        return cached.is_public
    end

    -- Make HTTP request to meeting-service
    local check_url = meeting_service_url .. "/check-room"
    local request_body = json.encode({
        room = room_name,
        event = "room_auth_check",
        secret = webhook_secret
    })

    module:log("debug", "Checking room access for: %s", room_name)

    local response_body = ""
    local response_code = 0

    -- Synchronous HTTP request
    local ok, err = pcall(function()
        http.request(check_url, {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#request_body)
            },
            body = request_body
        }, function(body, code, response, request)
            response_body = body or ""
            response_code = code or 0
        end)
    end)

    if not ok or response_code ~= 200 then
        -- If meeting-service is unreachable or room not found, default to PUBLIC
        module:log("warn", "Failed to check room access, defaulting to public. Error: %s, Code: %s", tostring(err), tostring(response_code))

        -- Cache as public
        room_cache[room_name] = {
            is_public = true,
            timestamp = os.time()
        }
        return true
    end

    -- Parse response
    local success, data = pcall(json.decode, response_body)
    if not success then
        module:log("warn", "Failed to parse response, defaulting to public")
        room_cache[room_name] = {
            is_public = true,
            timestamp = os.time()
        }
        return true
    end

    local is_public = data.is_public or data.public or false

    -- Cache the result
    room_cache[room_name] = {
        is_public = is_public,
        timestamp = os.time()
    }

    module:log("info", "Room %s access check: is_public=%s", room_name, tostring(is_public))
    return is_public
end

-- Hook into MUC room access
module:hook("muc-room-pre-create", function(event)
    local room_jid = event.room.jid
    local room_name = jid.split(room_jid)

    module:log("debug", "Room pre-create hook: %s", room_name)

    -- Check if room is public
    local is_public = check_room_access(room_name)

    if is_public then
        -- Allow guest access for this room
        event.room._data.allow_member_invites = true
        module:log("info", "Room %s is PUBLIC - guests allowed", room_name)
    else
        -- Require authentication for this room
        event.room._data.members_only = true
        module:log("info", "Room %s is PRIVATE - authentication required", room_name)
    end
end)

-- Hook into occupant pre-join to check access
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local stanza = event.stanza

    local room_jid = room.jid
    local room_name = jid.split(room_jid)
    local user_jid = occupant.bare_jid

    module:log("debug", "Occupant pre-join: %s trying to join %s", user_jid, room_name)

    -- Check if room is public
    local is_public = check_room_access(room_name)

    if is_public then
        -- Allow anyone to join public rooms
        module:log("debug", "Allowing %s to join public room %s", user_jid, room_name)
        return nil -- Allow
    end

    -- For private rooms, check if user is authenticated
    local is_guest = user_jid:find("@guest%.") ~= nil

    if is_guest then
        module:log("info", "Rejecting guest %s from private room %s", user_jid, room_name)
        return true -- Reject
    end

    module:log("debug", "Allowing authenticated user %s to join private room %s", user_jid, room_name)
    return nil -- Allow
end)

module:log("info", "Room Auth Check Module initialized")
