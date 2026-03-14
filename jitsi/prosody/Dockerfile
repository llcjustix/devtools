# Using official Jitsi Prosody image as base
ARG JITSI_PROSODY_VERSION=stable-9955
FROM jitsi/prosody:${JITSI_PROSODY_VERSION}

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
COPY mod_meeting_http_api.lua /prosody-plugins-custom/mod_meeting_http_api.lua

# Copy community plugins (from jitsi-contrib/prosody-plugins)
# token_affiliation: sets moderator role from JWT (teacher/admin = owner)
COPY mod_token_affiliation.lua /prosody-plugins-custom/mod_token_affiliation.lua
# jibri_autostart: auto-starts recording when moderator joins
COPY mod_jibri_autostart.lua /prosody-plugins-custom/mod_jibri_autostart.lua

# Set correct permissions
RUN chmod 644 /prosody-plugins-custom/*.lua && \
    chown prosody:prosody /prosody-plugins-custom/*.lua
