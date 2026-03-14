-- Nginx Lua script to validate room exists before serving Jitsi app
-- This runs at nginx level, before Jitsi React app loads

local http = require "resty.http"
local cjson = require "cjson"

-- Get room name from URI
local uri = ngx.var.uri
local room_name = string.match(uri, "^/([a-zA-Z0-9_%-]+)$")

-- Skip validation for static resources and special paths
if not room_name or
   room_name == "" or
   room_name:match("%.") or  -- Has file extension (static file)
   room_name == "http-bind" or
   room_name == "xmpp-websocket" or
   room_name == "config.js" or
   room_name == "interface_config.js" or
   room_name == "external_api.js" or
   room_name == "login.html" or
   room_name == "error.html" or
   room_name == "welcome.html" or
   room_name:match("^static/") or
   room_name:match("^libs/") or
   room_name:match("^css/") or
   room_name:match("^images/") then
    return  -- Allow access to static resources
end

ngx.log(ngx.INFO, "Validating room: ", room_name)

-- Check with meeting-service if room exists
local httpc = http.new()
httpc:set_timeout(2000)  -- 2 second timeout

local meeting_service_url = os.getenv("MEETING_SERVICE_URL") or "http://host.docker.internal:2022/meeting-service"
local validation_url = meeting_service_url .. "/webhooks/jitsi/check-room-status/" .. room_name

local res, err = httpc:request_uri(validation_url, {
    method = "GET",
    headers = {
        ["Accept"] = "application/json"
    }
})

if not res then
    ngx.log(ngx.ERR, "Failed to validate room: ", err)
    -- On error, redirect to error page with service error
    return ngx.redirect("/error.html?error=service-error&reason=Unable+to+validate+meeting&room=" .. ngx.escape_uri(room_name))
end

if res.status == 200 then
    -- Meeting exists, allow access
    ngx.log(ngx.INFO, "Room validated successfully: ", room_name)
    return
elseif res.status == 404 then
    -- Meeting not found
    ngx.log(ngx.WARN, "Room not found: ", room_name)
    return ngx.redirect("/error.html?error=meeting-not-found&reason=This+meeting+does+not+exist&room=" .. ngx.escape_uri(room_name))
elseif res.status == 410 then
    -- Meeting ended
    ngx.log(ngx.WARN, "Room ended: ", room_name)
    return ngx.redirect("/error.html?error=meeting-ended&reason=This+meeting+has+ended&room=" .. ngx.escape_uri(room_name))
else
    -- Other error
    ngx.log(ngx.ERR, "Unexpected response: ", res.status)
    return ngx.redirect("/error.html?error=service-error&reason=Unexpected+error&room=" .. ngx.escape_uri(room_name))
end
