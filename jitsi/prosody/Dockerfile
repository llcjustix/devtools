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

# Create custom plugins directory (use different path to avoid volume conflict)
RUN mkdir -p /usr/share/jitsi-meet/prosody-plugins-extra && \
    chown prosody:prosody /usr/share/jitsi-meet/prosody-plugins-extra

# Copy custom modules into image
COPY mod_jitsi_webhooks_enhanced.lua /usr/share/jitsi-meet/prosody-plugins-extra/mod_jitsi_webhooks_enhanced.lua
COPY mod_room_auth_check.lua /usr/share/jitsi-meet/prosody-plugins-extra/mod_room_auth_check.lua

# Set correct permissions
RUN chmod 644 /usr/share/jitsi-meet/prosody-plugins-extra/mod_jitsi_webhooks_enhanced.lua && \
    chmod 644 /usr/share/jitsi-meet/prosody-plugins-extra/mod_room_auth_check.lua && \
    chown prosody:prosody /usr/share/jitsi-meet/prosody-plugins-extra/*.lua
