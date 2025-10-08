-- Enhanced Jitsi Webhooks Module for Prosody
-- Backend-controlled integration: sends all events to meeting-service

local json = require("cjson.safe")
local http = require("socket.http")
local ltn12 = require("ltn12")

-- Configuration
local webhook_base_url = module:get_option_string("jitsi_webhook_url", "http://meeting-service:2031/webhooks/jitsi")
local webhook_secret = module:get_option_string("jitsi_webhook_secret", "")

module:log("info", "Enhanced Jitsi Webhooks Module loaded")
module:log("info", "Webhook URL: %s", webhook_base_url)

-- Utility: Send webhook
local function send_webhook(endpoint, payload)
    local url = webhook_base_url .. endpoint
    local request_body = json.encode(payload)

    local response_body = {}
    local res, code, response_headers = http.request({
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body),
            ["X-Webhook-Secret"] = webhook_secret
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    })

    if code == 200 then
        module:log("info", "Webhook sent successfully to %s", endpoint)
        return true, table.concat(response_body)
    else
        module:log("error", "Failed to send webhook to %s (HTTP %s)", endpoint, tostring(code))
        return false, nil
    end
end

-- Event: Room Created
module:hook("muc-room-created", function(event)
    local room = event.room
    local room_jid = room.jid
    local room_name = jid.split(room_jid)

    module:log("info", "Room created: %s", room_name)

    send_webhook("/room-created", {
        roomName = room_name,
        timestamp = os.time()
    })
end, 10)

-- Event: Validate Room Access
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local stanza = event.stanza

    local room_jid = room.jid
    local room_name = jid.split(room_jid)
    local user_jid = occupant.bare_jid
    local user_name = jid.split(user_jid)

    -- Extract JWT token from presence
    local jwt_token = nil
    local x = stanza:get_child("x", "http://jitsi.org/jitmeet/user-info")
    if x then
        jwt_token = x:get_child_text("jwt")
    end

    module:log("info", "Access validation for user %s in room %s", user_name, room_name)

    local success, response_body = send_webhook("/validate-access", {
        roomName = room_name,
        userId = user_name,
        userJid = user_jid,
        jwtToken = jwt_token,
        timestamp = os.time()
    })

    if success and response_body then
        local response = json.decode(response_body)
        if response then
            -- Store room configuration from backend
            if response.roomConfiguration then
                room._data.backend_config = response.roomConfiguration

                -- Build recording upload config from flat fields
                local room_config = response.roomConfiguration
                room._data.recording_upload_config = {
                    meetingId = room_config.recordingMeetingId,
                    fileServiceUrl = room_config.recordingFileServiceUrl,
                    uploadPath = room_config.recordingUploadPath,
                    bucket = room_config.recordingBucket,
                    storagePath = room_config.recordingStoragePath
                }

                module:log("info", "Room configuration received for %s (meetingId=%s)", room_name, room_config.recordingMeetingId)

                -- Enforce Prosody MUC room settings from backend
                if room_config.membersOnly ~= nil then
                    room:set_members_only(room_config.membersOnly)
                    module:log("info", "Set members_only=%s for room %s", tostring(room_config.membersOnly), room_name)
                end

                if room_config.moderated ~= nil then
                    room:set_moderated(room_config.moderated)
                    module:log("info", "Set moderated=%s for room %s", tostring(room_config.moderated), room_name)
                end

                if room_config.persistent ~= nil then
                    room:set_persistent(room_config.persistent)
                    module:log("info", "Set persistent=%s for room %s", tostring(room_config.persistent), room_name)
                end

                if room_config.hidden ~= nil then
                    room:set_hidden(room_config.hidden)
                    module:log("info", "Set hidden=%s for room %s", tostring(room_config.hidden), room_name)
                end

                if room_config.allowInvites ~= nil then
                    room:set_allow_member_invites(room_config.allowInvites)
                    module:log("info", "Set allow_invites=%s for room %s", tostring(room_config.allowInvites), room_name)
                end

                if room_config.publicRoom ~= nil then
                    room:set_public(room_config.publicRoom)
                    module:log("info", "Set public=%s for room %s", tostring(room_config.publicRoom), room_name)
                end

                if room_config.changeSubject ~= nil then
                    room:set_changesubject(room_config.changeSubject)
                    module:log("info", "Set changesubject=%s for room %s", tostring(room_config.changeSubject), room_name)
                end

                if room_config.historyLength and room_config.historyLength >= 0 then
                    room:set_history_length(room_config.historyLength)
                    module:log("info", "Set history_length=%d for room %s", room_config.historyLength, room_name)
                end

                -- Enforce meeting duration if maxDurationMinutes is set
                if room_config.maxDurationMinutes and room_config.maxDurationMinutes > 0 then
                    local duration_seconds = room_config.maxDurationMinutes * 60
                    module:log("info", "Scheduling room destruction for %s in %d minutes", room_name, room_config.maxDurationMinutes)

                    -- Schedule room destruction after duration
                    module:add_timer(duration_seconds, function()
                        module:log("warn", "Max duration reached for room %s, destroying room", room_name)
                        room:destroy(nil, "Maximum meeting duration exceeded")
                        return false -- Don't repeat timer
                    end)
                end
            end

            if response.allowed then
                module:log("info", "Access granted for user %s", user_name)
                return
            end
        end
    end

    module:log("warn", "Access denied for user %s in room %s", user_name, room_name)
    return true -- Block access
end, 10)

-- Event: User Joined
module:hook("muc-occupant-joined", function(event)
    local room = event.room
    local occupant = event.occupant

    local room_jid = room.jid
    local room_name = jid.split(room_jid)
    local user_jid = occupant.bare_jid
    local user_name = jid.split(user_jid)

    -- Determine if moderator
    local affiliation = room:get_affiliation(user_jid)
    local is_moderator = (affiliation == "owner" or affiliation == "admin")

    module:log("info", "User joined: %s in room %s (moderator: %s)", user_name, room_name, tostring(is_moderator))

    send_webhook("/user-joined", {
        roomName = room_name,
        userId = user_name,
        userJid = user_jid,
        isModerator = is_moderator,
        timestamp = os.time()
    })
end, 10)

-- Event: User Left
module:hook("muc-occupant-left", function(event)
    local room = event.room
    local occupant = event.occupant

    local room_jid = room.jid
    local room_name = jid.split(room_jid)
    local user_jid = occupant.bare_jid
    local user_name = jid.split(user_jid)

    module:log("info", "User left: %s from room %s", user_name, room_name)

    send_webhook("/user-left", {
        roomName = room_name,
        userId = user_name,
        userJid = user_jid,
        timestamp = os.time()
    })
end, 10)

-- Event: Room Destroyed
module:hook("muc-room-destroyed", function(event)
    local room = event.room
    local room_jid = room.jid
    local room_name = jid.split(room_jid)

    module:log("info", "Room destroyed: %s", room_name)

    send_webhook("/room-destroyed", {
        roomName = room_name,
        timestamp = os.time()
    })
end, 10)

-- Event: Moderator Changed
module:hook("muc-set-affiliation", function(event)
    local room = event.room
    local actor = event.actor
    local jid = event.jid
    local affiliation = event.affiliation

    local room_jid = room.jid
    local room_name = jid.split(room_jid)
    local user_name = jid.split(jid)

    local is_moderator = (affiliation == "owner" or affiliation == "admin")

    module:log("info", "Affiliation changed: %s in room %s (moderator: %s)", user_name, room_name, tostring(is_moderator))

    send_webhook("/moderator-changed", {
        roomName = room_name,
        userId = user_name,
        isModerator = is_moderator,
        timestamp = os.time()
    })
end, 10)

-- Event: Recording Status Changed (metadata.json creation)
module:hook("jibri-recording-status", function(event)
    local room = event.room
    local status = event.status
    local session_id = event.session_id

    local room_jid = room.jid
    local room_name = jid.split(room_jid)

    module:log("info", "Recording status changed: %s (status: %s)", room_name, status)

    -- Send webhook to backend
    send_webhook("/recording", {
        roomName = room_name,
        status = status,
        sessionId = session_id,
        timestamp = os.time()
    })

    -- Create metadata.json when recording starts
    if status == "on" then
        local upload_config = room._data.recording_upload_config

        if not upload_config then
            module:log("error", "No recording upload config found for room %s", room_name)
            return
        end

        local recording_dir = "/tmp/recordings"
        local session_id_safe = session_id or "session-" .. room_name .. "-" .. tostring(os.time())

        -- Replace {sessionId} placeholder in storagePath from backend
        -- Backend sends: /meetings/{meetingId}/{sessionId}/
        local storage_path = upload_config.storagePath
        if storage_path then
            storage_path = string.gsub(storage_path, "{sessionId}", session_id_safe)
        else
            -- Fallback if no storagePath provided
            storage_path = "recordings/" .. room_name .. "/" .. session_id_safe .. "/"
        end

        -- Combine backend config with Prosody webhook config
        local metadata = {
            roomName = room_name,
            meetingId = upload_config.meetingId,
            sessionId = session_id_safe,
            startTime = os.time(),
            recordingUploadConfig = {
                meetingId = upload_config.meetingId,
                fileServiceUrl = upload_config.fileServiceUrl,
                uploadPath = upload_config.uploadPath or "/api/files/upload",
                bucket = upload_config.bucket or "recordings",
                storagePath = storage_path,
                webhookUrl = webhook_base_url .. "/recording",
                webhookSecret = webhook_secret
            }
        }

        -- Write metadata.json
        local metadata_json = json.encode(metadata)
        local metadata_file = io.open(recording_dir .. "/metadata.json", "w")

        if metadata_file then
            metadata_file:write(metadata_json)
            metadata_file:close()
            module:log("info", "Created metadata.json for recording: %s", room_name)
        else
            module:log("error", "Failed to create metadata.json for room %s", room_name)
        end
    end
end, 10)

module:log("info", "Enhanced Jitsi Webhooks Module initialized")
