#!/bin/bash
# Patch the jitsi-meet.cfg.lua template to add custom modules to MUC component

CONFIG_FILE="/defaults/conf.d/jitsi-meet.cfg.lua"

# Use awk to add modules after "modules_enabled = {" in the MUC component section
awk '
/{{ \.Env\.XMPP_MUC_DOMAIN }}" "muc"/ {
    in_muc=1
}
in_muc && /modules_enabled = \{/ {
    print
    print "        \"jitsi_webhooks_enhanced\";"
    print "        \"room_access_validator\";"
    in_muc=0
    next
}
{print}
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "Patched MUC component configuration"
