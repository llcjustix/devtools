-- mod_jitsi_webhooks.lua
-- Complete Prosody module for sending all Jitsi/Prosody events to backend
-- Supports: room lifecycle, participants, moderator changes
-- Note: Chat and whiteboard are captured by Jibri and uploaded to file-service with recording artifacts
--
-- Duration Enforcement:
-- - Backend provides maxDurationMinutes in room-created response
-- - Prosody destroys room after duration expires using module:add_timer()
-- - When room is destroyed, backend receives room-destroyed webhook and marks meeting as COMPLETED
--
-- Authentication (Private Meetings):
-- - Public meetings: No authentication required
-- - Private meetings: Requires JWT Bearer token
-- - Frontend adds token to Jitsi URL: http://meet.domain.com/room?jwt={token}
-- - Prosody extracts token from session and sends in validate-access webhook
-- - Backend validates token and checks if user is invited
--
-- File Service Integration (Jibri Recording Uploads):
-- - Jibri finalize script uploads recordings to file-service
-- - Path structure: /roomName/sessionId/video.mp4, chat.json, whiteboard.json
-- - File-service URL must be accessible from Jibri container
--
-- Installation:
-- 1. Copy this file to: /usr/share/jitsi-meet/prosody-plugins/mod_jitsi_webhooks.lua
-- 2. Add to prosody config (/etc/prosody/prosody.cfg.lua):
--    modules_enabled = { "jitsi_webhooks" }
--    jitsi_webhook_url = "http://meeting-service:2031/webhooks/jitsi"
--    jitsi_webhook_secret = "your-secret-key"
--    jitsi_file_service_url = "http://file-service:2027"  -- For Jibri uploads
-- 3. Restart Prosody: systemctl restart prosody

local http = require "net.http";
local json = require "util.json";
local jid_split = require "util.jid".split;
local st = require "util.stanza";

-- Configuration
local webhook_base_url = module:get_option_string("jitsi_webhook_url", "http://localhost:8080/webhooks/jitsi");
local webhook_secret = module:get_option_string("jitsi_webhook_secret", "");
local webhook_timeout = module:get_option_number("jitsi_webhook_timeout", 5);
local file_service_url = module:get_option_string("jitsi_file_service_url", "http://file-service:2027");

module:log("info", "Jitsi Webhooks Module loaded. Webhook URL: %s, File Service URL: %s",
    webhook_base_url, file_service_url);

-- Helper: Call webhook
local function call_webhook(endpoint, payload, callback)
    local url = webhook_base_url .. endpoint;
    local body = json.encode(payload);

    local headers = {
        ["Content-Type"] = "application/json";
        ["Content-Length"] = tostring(#body);
    };

    if webhook_secret and webhook_secret ~= "" then
        headers["X-Webhook-Secret"] = webhook_secret;
    end

    module:log("debug", "Calling webhook: %s", url);

    http.request(url, {
        method = "POST",
        headers = headers,
        body = body
    }, callback or function(response_body, code, response)
        if code == 200 then
            module:log("debug", "Webhook success: %s", endpoint);
        else
            module:log("warn", "Webhook failed: %s (code=%s)", endpoint, code);
        end
    end);
end

-- Helper: Get room name from JID
local function get_room_name(room_jid)
    local node, host = jid_split(room_jid);
    return node;
end

-- Helper: Check if user is moderator
local function is_moderator(room, occupant)
    if not occupant then return false; end
    local affiliation = room:get_affiliation(occupant.bare_jid);
    local role = occupant.role;
    return affiliation == "owner" or affiliation == "admin" or role == "moderator";
end

-- ========== ROOM LIFECYCLE WEBHOOKS ==========

-- 1. Room Created - Get room configuration from backend
module:hook("muc-room-created", function(event)
    local room = event.room;
    local room_name = get_room_name(room.jid);

    module:log("info", "Room created: %s", room_name);

    local payload = {
        roomName = room_name,
        roomJid = room.jid,
        timestamp = os.time()
    };

    call_webhook("/room-created", payload, function(response_body, code, response)
        if code == 200 and response_body then
            local success, config = pcall(json.decode, response_body);
            if success and config then
                module:log("info", "Room configuration received for: %s", room_name);

                -- Store meetingId for file-service uploads (used as referenceId)
                if config.meetingId then
                    room._data.meeting_id = config.meetingId;
                    module:log("info", "Stored meetingId for room %s: %s", room_name, config.meetingId);
                end

                -- Apply configuration from backend
                if config.maxParticipants then
                    room._data.max_occupants = config.maxParticipants;
                end

                -- Store isPublic flag for validate-access optimization
                room._data.is_public = (config.isPublic ~= false);

                -- Configure room access based on public/private setting
                if config.isPublic == false then
                    -- Private meeting - restrict to members only
                    room:set_members_only(true);
                    module:log("info", "Room %s configured as PRIVATE (members-only)", room_name);
                else
                    -- Public meeting - allow anyone to join
                    room:set_members_only(false);
                    module:log("info", "Room %s configured as PUBLIC (open access)", room_name);
                end

                -- Duration enforcement: Destroy room after maxDurationMinutes expires
                if config.maxDurationMinutes and config.maxDurationMinutes > 0 then
                    local duration_seconds = config.maxDurationMinutes * 60;
                    module:log("info", "Room %s has duration limit: %d minutes (%d seconds)",
                        room_name, config.maxDurationMinutes, duration_seconds);

                    -- Schedule room destruction
                    module:add_timer(duration_seconds, function()
                        module:log("warn", "Duration limit reached for room %s, destroying room...", room_name);

                        -- Destroy room with reason
                        room:destroy(nil, "Meeting duration limit has been reached");

                        -- Backend will receive room-destroyed webhook automatically
                        return false; -- Don't repeat timer
                    end);

                    module:log("info", "Scheduled room destruction for %s in %d minutes", room_name, config.maxDurationMinutes);
                end

                -- Set moderators (owners/admins)
                if config.moderators then
                    for _, moderator_jid in ipairs(config.moderators) do
                        room:set_affiliation(true, moderator_jid, "owner");
                    end
                end

                module:log("info", "Room configured: %s (meetingId=%s, isPublic=%s, moderators=%d, maxParticipants=%s)",
                    room_name, tostring(config.meetingId or "N/A"),
                    tostring(config.isPublic ~= false),
                    config.moderators and #config.moderators or 0,
                    tostring(config.maxParticipants or "unlimited"));
            end
        end
    end);
end, 10);

-- 2. Validate Access - Check if user can join
-- IMPORTANT: ALWAYS validate meeting status first (cancelled, expired, completed)
-- THEN check public/private access rules
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room;
    local occupant = event.occupant;
    local room_name = get_room_name(room.jid);
    local user_jid = occupant.bare_jid;
    local user_name = occupant.nick or jid_split(user_jid);

    module:log("debug", "Validating access: room=%s, user=%s", room_name, user_jid);

    -- Get room privacy status
    local is_public = room._data.is_public;
    if is_public == nil then
        is_public = true; -- Default to public if not set (backward compatibility)
    end

    -- Extract Bearer JWT token from session (needed for private meetings)
    -- After mod_token_verification validates the JWT, user context is stored in session
    local bearer_token = nil;
    local session = event.origin;

    -- Try to get the raw JWT from the session
    -- mod_token_verification stores it in session.auth_token after validation
    if session and session.auth_token then
        bearer_token = session.auth_token;
        module:log("debug", "Extracted bearer token from session.auth_token");
    elseif session and session.jitsi_meet_context_user then
        -- If auth_token not available, try to reconstruct from user context
        bearer_token = "authenticated";  -- Flag that user has valid token
        module:log("debug", "User authenticated via Jitsi context");
    end

    -- Private meeting without token: Reject immediately (no webhook needed)
    if not is_public and (not bearer_token or bearer_token == "") then
        module:log("warn", "Access denied (private meeting, no token): room=%s, user=%s", room_name, user_jid);
        return true; -- Block join
    end

    -- ALWAYS call webhook to validate meeting status (CANCELLED, EXPIRED, COMPLETED)
    -- Even for public meetings - we must check if meeting is still valid
    local payload = {
        meetingId = room._data.meeting_id,  -- Stored from room-created response
        roomName = room_name,                -- Fallback
        userJid = user_jid,
        userName = user_name,
        bearerToken = bearer_token,          -- JWT token (null for public, required for private)
        timestamp = os.time()
    };

    module:log("debug", "Calling validate-access webhook: isPublic=%s, hasToken=%s",
        tostring(is_public), tostring(bearer_token ~= nil));

    -- Synchronous validation (blocking)
    local validated = false;
    local validation_reason = nil;

    call_webhook("/validate-access", payload, function(response_body, code, response)
        if code == 200 and response_body then
            local success, data = pcall(json.decode, response_body);
            if success and data then
                validated = data.allowed or false;
                validation_reason = data.reason or "Access denied";
            else
                validated = false; -- Fail closed on parse error (security)
                validation_reason = "Invalid server response";
            end
        else
            validated = false; -- Fail closed on webhook error (security)
            validation_reason = "Server unavailable";
        end
    end);

    -- Wait for validation (simple busy wait - consider async in production)
    local timeout_time = os.time() + webhook_timeout;
    while validation_reason == nil and os.time() < timeout_time do
        -- Wait for callback
    end

    if not validated then
        module:log("warn", "Access denied: room=%s, user=%s, reason=%s",
            room_name, user_jid, validation_reason);
        return true; -- Block join
    end

    module:log("info", "Access granted: room=%s, user=%s", room_name, user_jid);
end, 10);

-- 3. User Joined
module:hook("muc-occupant-joined", function(event)
    local room = event.room;
    local occupant = event.occupant;
    local room_name = get_room_name(room.jid);
    local user_jid = occupant.bare_jid;
    local user_name = occupant.nick or jid_split(user_jid);

    module:log("info", "User joined: room=%s, user=%s", room_name, user_name);

    local payload = {
        roomName = room_name,
        userJid = user_jid,
        userName = user_name,
        isModerator = is_moderator(room, occupant),
        timestamp = os.time()
    };

    call_webhook("/user-joined", payload);
end);

-- 4. User Left
module:hook("muc-occupant-left", function(event)
    local room = event.room;
    local occupant = event.occupant;
    local room_name = get_room_name(room.jid);
    local user_jid = occupant.bare_jid;
    local user_name = occupant.nick or jid_split(user_jid);

    module:log("info", "User left: room=%s, user=%s", room_name, user_name);

    local payload = {
        roomName = room_name,
        userJid = user_jid,
        userName = user_name,
        timestamp = os.time()
    };

    call_webhook("/user-left", payload);
end);

-- 5. Room Destroyed
module:hook("muc-room-destroyed", function(event)
    local room = event.room;
    local room_name = get_room_name(room.jid);

    module:log("info", "Room destroyed: %s", room_name);

    local payload = {
        roomName = room_name,
        roomJid = room.jid,
        reason = "all_users_left",
        timestamp = os.time()
    };

    call_webhook("/room-destroyed", payload);
end);

-- 6. Moderator Status Changed
module:hook("muc-set-affiliation", function(event)
    local room = event.room;
    local actor = event.actor;
    local jid = event.jid;
    local affiliation = event.affiliation;
    local room_name = get_room_name(room.jid);

    -- Only track owner/admin changes (moderator status)
    if affiliation == "owner" or affiliation == "admin" or affiliation == "member" then
        local is_moderator = (affiliation == "owner" or affiliation == "admin");
        local user_name = jid_split(jid);
        local changed_by = actor and jid_split(actor) or "system";

        module:log("info", "Moderator changed: room=%s, user=%s, isModerator=%s, by=%s",
            room_name, user_name, tostring(is_moderator), changed_by);

        local payload = {
            roomName = room_name,
            userJid = jid,
            userName = user_name,
            isModerator = is_moderator,
            changedBy = actor,
            timestamp = os.time()
        };

        call_webhook("/moderator-changed", payload);
    end
end);

module:log("info", "Jitsi Webhooks Module initialized successfully");
