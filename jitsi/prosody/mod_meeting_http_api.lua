-- Meeting HTTP API Module for Prosody
-- Provides HTTP endpoint for backend to force-destroy Jitsi rooms
-- Must be loaded on the main host (meet.jitsi), NOT on MUC component
--
-- Endpoint: POST /meeting_http_api/destroy-room
-- Body: { "roomName": "abc-defg-hij", "secret": "...", "reason": "..." }

local json = require("cjson.safe")

local webhook_secret = os.getenv("JITSI_WEBHOOK_SECRET") or module:get_option_string("jitsi_webhook_secret", "")
local muc_domain = module:get_option_string("muc_mapper_domain_base", "meet.jitsi")
local muc_host = "muc." .. muc_domain

module:depends("http")

module:provides("http", {
    default_path = "/meeting-api";
    route = {
        ["POST /destroy-room"] = function(event)
            local request = event.request
            local body = request.body

            if not body or #body == 0 then
                return { status_code = 400; headers = { content_type = "application/json" }; body = '{"error":"empty body"}' }
            end

            local data = json.decode(body)
            if not data then
                return { status_code = 400; headers = { content_type = "application/json" }; body = '{"error":"invalid json"}' }
            end

            -- Verify secret
            local req_secret = data.secret or ""
            if webhook_secret ~= "" and req_secret ~= webhook_secret then
                module:log("warn", "Destroy-room: invalid secret")
                return { status_code = 401; headers = { content_type = "application/json" }; body = '{"error":"unauthorized"}' }
            end

            local room_name = data.roomName
            local reason = data.reason or "Meeting ended by server"

            if not room_name or room_name == "" then
                return { status_code = 400; headers = { content_type = "application/json" }; body = '{"error":"roomName required"}' }
            end

            local room_jid = room_name .. "@" .. muc_host
            module:log("info", "Destroy-room: looking up room_jid=%s", room_jid)

            -- Find the MUC room
            local room = nil
            local muc_host_session = prosody.hosts[muc_host]

            if muc_host_session then
                local muc_mod = muc_host_session.modules and muc_host_session.modules.muc
                if muc_mod then
                    -- Try rooms table
                    if type(muc_mod.rooms) == "table" then
                        room = muc_mod.rooms[room_jid]
                    end
                    -- Try get_room function
                    if not room and type(muc_mod.get_room) == "function" then
                        room = muc_mod.get_room(room_jid)
                    end
                    -- Try each_room iterator
                    if not room and type(muc_mod.each_room) == "function" then
                        for r in muc_mod.each_room() do
                            if r.jid == room_jid then
                                room = r
                                break
                            end
                        end
                    end
                else
                    module:log("warn", "Destroy-room: MUC module not found on host %s", muc_host)
                end
            else
                module:log("warn", "Destroy-room: host %s not found", muc_host)
            end

            if not room then
                module:log("info", "Destroy-room: room %s not found (may already be empty)", room_name)
                return { status_code = 404; headers = { content_type = "application/json" }; body = '{"status":"not_found","message":"room not active"}' }
            end

            module:log("info", "Force-destroying room %s: %s", room_name, reason)
            room:destroy(nil, reason)

            return { status_code = 200; headers = { content_type = "application/json" }; body = '{"status":"destroyed","roomName":"' .. room_name .. '"}' }
        end;

        -- Health check
        ["GET /health"] = function(event)
            return { status_code = 200; headers = { content_type = "application/json" }; body = '{"status":"ok"}' }
        end;
    }
})

module:log("info", "Meeting HTTP API module loaded (endpoints: POST /meeting-api/destroy-room, GET /meeting-api/health)")
