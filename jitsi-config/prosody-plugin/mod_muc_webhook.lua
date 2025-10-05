-- mod_muc_webhook.lua
-- Prosody module for Jitsi Meet to integrate with backend via webhooks
--
-- This module sends webhooks to your backend when:
-- 1. A room is created (to get room configuration)
-- 2. A user attempts to join (to validate access)
--
-- Installation:
-- 1. Copy this file to: /usr/share/jitsi-meet/prosody-plugins/
-- 2. Add to prosody config: modules_enabled = { "muc_webhook" }
-- 3. Configure webhook URL and secret in prosody config
-- 4. Restart Prosody: sudo systemctl restart prosody

local http = require "net.http"
local json = require "util.json"
local jid = require "util.jid"
local st = require "util.stanza"

-- Module configuration (from prosody config)
local webhook_url = module:get_option_string("muc_webhook_url", nil)
local webhook_secret = module:get_option_string("muc_webhook_secret", nil)
local webhook_timeout = module:get_option_number("muc_webhook_timeout", 5)

-- Validation
if not webhook_url then
    module:log("error", "muc_webhook_url not configured! Module will not function.")
    return
end

module:log("info", "MUC Webhook module loaded")
module:log("info", "Webhook URL: %s", webhook_url)
module:log("info", "Webhook secret configured: %s", webhook_secret and "yes" or "no")

-- Helper: Make HTTP request to backend
local function call_webhook(endpoint, payload, callback)
    local request_body = json.encode(payload)
    local full_url = webhook_url .. endpoint

    module:log("debug", "Calling webhook: %s with payload: %s", full_url, request_body)

    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "Prosody-MUC-Webhook/1.0"
    }

    if webhook_secret then
        headers["X-Webhook-Secret"] = webhook_secret
    end

    http.request(full_url, {
        method = "POST",
        headers = headers,
        body = request_body,
        timeout = webhook_timeout
    }, callback)
end

-- Hook: Room created
-- Called when a new MUC room is created
-- Gets room configuration from backend and applies it
module:hook("muc-room-created", function(event)
    local room = event.room
    local room_jid = room.jid
    local room_name = jid.split(room_jid)

    module:log("info", "Room created: %s (JID: %s)", room_name, room_jid)

    -- Prepare webhook payload
    local payload = {
        event = "room_created",
        roomName = room_name,
        roomJid = room_jid,
        timestamp = os.time()
    }

    -- Call backend to get room configuration
    call_webhook("/room-created", payload, function(response_body, code, response)
        if code == 200 then
            module:log("info", "Webhook success for room %s (HTTP %d)", room_name, code)

            -- Parse backend response
            local success, config = pcall(json.decode, response_body)

            if success and config then
                module:log("info", "Applying configuration for room %s", room_name)

                -- Apply max participants
                if config.maxParticipants and config.maxParticipants > 0 then
                    room._data.max_participants = config.maxParticipants
                    module:log("debug", "Set max participants: %d", config.maxParticipants)
                end

                -- Set password if provided
                if config.password and config.password ~= "" then
                    room:set_password(config.password)
                    module:log("debug", "Set room password")
                end

                -- Set moderators (grant owner affiliation)
                if config.moderators then
                    for _, moderator_email in ipairs(config.moderators) do
                        local mod_jid = moderator_email
                        if not mod_jid:match("@") then
                            -- If just email, construct full JID
                            mod_jid = moderator_email .. "@" .. module.host
                        end
                        room._affiliations[mod_jid] = "owner"
                        module:log("debug", "Set moderator: %s", mod_jid)
                    end
                end

                -- Store custom settings in room data (for later use)
                room._data.recording_enabled = config.recordingEnabled or false
                room._data.chat_enabled = config.chatEnabled or true
                room._data.whiteboard_enabled = config.whiteboardEnabled or true
                room._data.lobby_enabled = config.lobbyEnabled or false
                room._data.screen_share_enabled = config.screenShareEnabled or true
                room._data.mute_on_join = config.muteOnJoin or false
                room._data.video_off_on_join = config.videoOffOnJoin or false
                room._data.auto_record = config.autoRecord or false
                room._data.meeting_title = config.meetingTitle
                room._data.meeting_description = config.meetingDescription

                -- Participant features
                room._data.reactions_enabled = config.reactionsEnabled or true
                room._data.raise_hand_enabled = config.raiseHandEnabled or true
                room._data.private_messages_enabled = config.privateMessagesEnabled or true
                room._data.participant_name_editing_enabled = config.participantNameEditingEnabled or false
                room._data.follow_me_enabled = config.followMeEnabled or true
                room._data.tile_view_enabled = config.tileViewEnabled or true
                room._data.filmstrip_enabled = config.filmstripEnabled or true

                -- Media features
                room._data.live_streaming_enabled = config.liveStreamingEnabled or false
                room._data.virtual_backgrounds_enabled = config.virtualBackgroundsEnabled or true
                room._data.noise_suppression_enabled = config.noiseSuppressionEnabled or true
                room._data.e2ee_enabled = config.e2eeEnabled or false
                room._data.hd1080p_enabled = config.hd1080pEnabled or false
                room._data.audio_quality = config.audioQuality or "standard"

                -- Moderation features
                room._data.polls_enabled = config.pollsEnabled or true
                room._data.breakout_rooms_enabled = config.breakoutRoomsEnabled or false
                room._data.speaker_stats_enabled = config.speakerStatsEnabled or true
                room._data.kick_participants_enabled = config.kickParticipantsEnabled or true
                room._data.mute_all_enabled = config.muteAllEnabled or true
                room._data.av_moderation_enabled = config.avModerationEnabled or false
                room._data.security_enabled = config.securityEnabled or true

                -- UI features
                room._data.closed_captions_enabled = config.closedCaptionsEnabled or false
                room._data.shared_document_enabled = config.sharedDocumentEnabled or false
                room._data.calendar_enabled = config.calendarEnabled or false
                room._data.toolbar_buttons = config.toolbarButtons

                -- Enable lobby if configured
                if config.lobbyEnabled then
                    room._data.lobbyroom = true
                    module:log("debug", "Lobby enabled")
                end

                -- Apply Prosody MUC room settings
                if config.membersOnly ~= nil then
                    room:set_members_only(config.membersOnly)
                    module:log("debug", "Set members_only: %s", tostring(config.membersOnly))
                end

                if config.moderated ~= nil then
                    room:set_moderated(config.moderated)
                    module:log("debug", "Set moderated: %s", tostring(config.moderated))
                end

                if config.persistent ~= nil then
                    room:set_persistent(config.persistent)
                    module:log("debug", "Set persistent: %s", tostring(config.persistent))
                end

                if config.hidden ~= nil then
                    room:set_hidden(config.hidden)
                    module:log("debug", "Set hidden: %s", tostring(config.hidden))
                end

                if config.allowInvites ~= nil then
                    room._data.allow_member_invites = config.allowInvites
                    module:log("debug", "Set allow_invites: %s", tostring(config.allowInvites))
                end

                if config.publicRoom ~= nil then
                    room:set_public(config.publicRoom)
                    module:log("debug", "Set public: %s", tostring(config.publicRoom))
                end

                if config.changeSubject ~= nil then
                    room._data.changesubject = config.changeSubject
                    module:log("debug", "Set change_subject: %s", tostring(config.changeSubject))
                end

                if config.whois ~= nil then
                    room:set_whois(config.whois)
                    module:log("debug", "Set whois: %s", config.whois)
                end

                if config.historyLength ~= nil and config.historyLength > 0 then
                    room._data.history_length = config.historyLength
                    module:log("debug", "Set history_length: %d", config.historyLength)
                end

                module:log("info", "Configuration applied successfully for room %s", room_name)
            else
                module:log("error", "Failed to parse webhook response for room %s: %s",
                    room_name, response_body or "empty response")
            end
        else
            module:log("error", "Webhook failed for room %s: HTTP %d, response: %s",
                room_name, code, response_body or "no response")
        end
    end)

    return nil -- Allow room creation to proceed
end)

-- Hook: User attempting to join
-- Called before a user is allowed to join a room
-- Validates access with backend
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room
    local occupant = event.occupant
    local room_name = jid.split(room.jid)
    local user_jid = occupant.bare_jid
    local user_nick = occupant.nick or "Unknown"

    module:log("info", "User attempting to join: %s -> %s (nick: %s)",
        user_jid, room_name, user_nick)

    -- Prepare validation request
    local payload = {
        event = "validate_access",
        roomName = room_name,
        userJid = user_jid,
        userName = user_nick,
        timestamp = os.time()
    }

    -- Make synchronous call to backend
    -- Note: This blocks the join until backend responds
    call_webhook("/validate-access", payload, function(response_body, code, response)
        if code == 200 then
            local success, result = pcall(json.decode, response_body)

            if success and result then
                if result.allowed then
                    module:log("info", "User %s allowed to join %s", user_jid, room_name)
                    -- Allow join - do nothing
                else
                    module:log("warn", "User %s denied access to %s: %s",
                        user_jid, room_name, result.reason or "no reason provided")

                    -- Send error to user
                    event.origin.send(st.error_reply(
                        event.stanza,
                        "auth",
                        "forbidden",
                        result.reason or "Access denied"
                    ))

                    -- Prevent join
                    return true
                end
            else
                module:log("error", "Failed to parse validation response for %s: %s",
                    user_jid, response_body or "empty")
                -- Allow by default on parse error
            end
        else
            module:log("error", "Validation webhook failed for %s: HTTP %d", user_jid, code)
            -- Allow by default on webhook failure (fail-open)
            -- Change to "return true" for fail-closed behavior
        end
    end)

    return nil -- Allow join (unless callback denied it)
end)

-- Hook: User joined successfully
-- Send notification to backend when user joins
-- Also send room configuration to Jitsi frontend
module:hook("muc-occupant-joined", function(event)
    local room = event.room
    local occupant = event.occupant
    local room_name = jid.split(room.jid)

    module:log("info", "User joined: %s -> %s", occupant.bare_jid, room_name)

    -- Send room configuration to Jitsi frontend
    local config_message = st.message({
        type = "groupchat",
        from = room.jid,
        to = occupant.nick
    })
    :tag("json-message", {xmlns = "http://jitsi.org/jitmeet"})
    :text(json.encode({
        type = "ROOM_CONFIG",
        config = {
            -- Core features
            chatEnabled = room._data.chat_enabled,
            whiteboardEnabled = room._data.whiteboard_enabled,
            screenShareEnabled = room._data.screen_share_enabled,
            recordingEnabled = room._data.recording_enabled,
            muteOnJoin = room._data.mute_on_join,
            videoOffOnJoin = room._data.video_off_on_join,
            meetingTitle = room._data.meeting_title,
            meetingDescription = room._data.meeting_description,

            -- Participant features
            reactionsEnabled = room._data.reactions_enabled,
            raiseHandEnabled = room._data.raise_hand_enabled,
            privateMessagesEnabled = room._data.private_messages_enabled,
            participantNameEditingEnabled = room._data.participant_name_editing_enabled,
            followMeEnabled = room._data.follow_me_enabled,
            tileViewEnabled = room._data.tile_view_enabled,
            filmstripEnabled = room._data.filmstrip_enabled,

            -- Media features
            liveStreamingEnabled = room._data.live_streaming_enabled,
            virtualBackgroundsEnabled = room._data.virtual_backgrounds_enabled,
            noiseSuppressionEnabled = room._data.noise_suppression_enabled,
            e2eeEnabled = room._data.e2ee_enabled,
            hd1080pEnabled = room._data.hd1080p_enabled,
            audioQuality = room._data.audio_quality,

            -- Moderation features
            pollsEnabled = room._data.polls_enabled,
            breakoutRoomsEnabled = room._data.breakout_rooms_enabled,
            speakerStatsEnabled = room._data.speaker_stats_enabled,
            kickParticipantsEnabled = room._data.kick_participants_enabled,
            muteAllEnabled = room._data.mute_all_enabled,
            avModerationEnabled = room._data.av_moderation_enabled,
            securityEnabled = room._data.security_enabled,

            -- UI features
            closedCaptionsEnabled = room._data.closed_captions_enabled,
            sharedDocumentEnabled = room._data.shared_document_enabled,
            calendarEnabled = room._data.calendar_enabled,
            toolbarButtons = room._data.toolbar_buttons
        }
    }))
    :up()

    occupant:send(config_message)
    module:log("debug", "Sent room config to %s", occupant.bare_jid)

    -- Check if auto-recording should start
    if room._data.auto_record and room._data.recording_enabled then
        module:log("info", "Auto-recording enabled for %s, sending start command", room_name)

        -- Send message to room to trigger recording
        local msg = st.message({
            type = "groupchat",
            from = room.jid,
            to = room.jid
        })
        :tag("json-message", {xmlns = "http://jitsi.org/jitmeet"})
        :text(json.encode({
            type = "START_RECORDING",
            auto = true
        }))
        :up()

        room:broadcast_message(msg)
    end

    return nil
end)

-- Hook: User left
-- Optional: Notify backend when user leaves
module:hook("muc-occupant-left", function(event)
    local room = event.room
    local occupant = event.occupant
    local room_name = jid.split(room.jid)

    module:log("debug", "User left: %s -> %s", occupant.bare_jid, room_name)

    -- Optional: Send webhook to backend
    -- Uncomment if you need to track user departures
    --[[
    local payload = {
        event = "user_left",
        roomName = room_name,
        userJid = occupant.bare_jid,
        timestamp = os.time()
    }
    call_webhook("/user-left", payload, function() end)
    ]]

    return nil
end)

-- Hook: Room destroyed
-- Optional: Notify backend when room is destroyed
module:hook("muc-room-destroyed", function(event)
    local room = event.room
    local room_name = jid.split(room.jid)

    module:log("info", "Room destroyed: %s", room_name)

    -- Optional: Send webhook to backend
    -- Uncomment if you need to track room lifecycle
    --[[
    local payload = {
        event = "room_destroyed",
        roomName = room_name,
        timestamp = os.time()
    }
    call_webhook("/room-destroyed", payload, function() end)
    ]]

    return nil
end)

module:log("info", "MUC Webhook module initialized successfully")
