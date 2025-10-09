# Using official Jitsi Prosody image as base
FROM jitsi/prosody:stable-9258

# Fix repository issues and install Lua dependencies
RUN rm -f /etc/apt/sources.list.d/prosody.list && \
    rm -f /etc/apt/sources.list.d/backports.list && \
    rm -f /etc/apt/sources.list.d/jitsi-stable.list && \
    echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bullseye-updates main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        lua-cjson \
        lua-sec \
        lua-socket \
    && rm -rf /var/lib/apt/lists/*

# Use the standard Jitsi prosody-plugins-custom directory
# This directory is automatically added to plugin_paths by Jitsi's entrypoint
RUN mkdir -p /prosody-plugins-custom && \
    chown prosody:prosody /prosody-plugins-custom

# Copy custom modules into the standard custom plugins directory
COPY mod_jitsi_webhooks_enhanced.lua /prosody-plugins-custom/mod_jitsi_webhooks_enhanced.lua
COPY mod_room_access_validator.lua /prosody-plugins-custom/mod_room_access_validator.lua

# Copy and run script to patch the jitsi-meet.cfg.lua template
COPY patch-muc-config.sh /tmp/patch-muc-config.sh
RUN chmod +x /tmp/patch-muc-config.sh && /tmp/patch-muc-config.sh && rm /tmp/patch-muc-config.sh

# Set correct permissions
RUN chmod 644 /prosody-plugins-custom/mod_jitsi_webhooks_enhanced.lua && \
    chmod 644 /prosody-plugins-custom/mod_room_access_validator.lua && \
    chown prosody:prosody /prosody-plugins-custom/*.lua
