-- Custom configuration to add webhook modules to MUC component
-- This file is loaded after the main configuration

-- Reconfigure the main MUC component to include our custom modules
Component "muc.meet.jitsi" "muc"
    restrict_room_creation = true
    storage = "memory"
    modules_enabled = {
        "muc_meeting_id";
        "token_verification";
        "polls";
        "muc_domain_mapper";
        "muc_password_whitelist";
        -- Add our custom webhook modules
        "jitsi_webhooks_enhanced";
        "room_access_validator";
    }

    rate_limit_cache_size = 10000;
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true

    muc_password_whitelist = {
        "focus@auth.meet.jitsi";
    }
