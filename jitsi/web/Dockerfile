ARG JITSI_WEB_VERSION=stable-9955
FROM jitsi/web:${JITSI_WEB_VERSION}

# Build arguments for service URLs and token config (optional, for production)
ARG MEETING_SERVICE_URL
ARG AUTH_SERVICE_URL
ARG LEARNX_TOKEN_KEY
ARG LEARNX_REFRESH_KEY

# Copy custom config overrides (disable recording UI prompts, dynamic URLs)
COPY custom-config.js /usr/share/jitsi-meet/custom-config.js

# Copy custom CSS styles
COPY custom-styles.css /usr/share/jitsi-meet/css/custom-styles.css

# Copy LearnX Meets logos and icons
COPY images/learnx-logo.svg /usr/share/jitsi-meet/images/learnx-logo.svg
COPY images/learnx-icon.svg /usr/share/jitsi-meet/images/learnx-icon.svg
COPY images/learnx-watermark.svg /usr/share/jitsi-meet/images/learnx-watermark.svg

# Copy custom branding files
COPY title.html /usr/share/jitsi-meet/title.html
COPY manifest.json /usr/share/jitsi-meet/manifest.json

# Copy authentication and validation files
COPY jitsi-auth.js /usr/share/jitsi-meet/jitsi-auth.js
COPY jitsi-room-validator.js /usr/share/jitsi-meet/jitsi-room-validator.js
COPY login.html /usr/share/jitsi-meet/login.html
COPY error.html /usr/share/jitsi-meet/error.html

# Copy welcome/landing and schedule pages
COPY welcome.html /usr/share/jitsi-meet/welcome.html
COPY schedule.html /usr/share/jitsi-meet/schedule.html

# Copy Nginx Lua room validator for server-side validation
COPY validate-room.lua /usr/share/jitsi-meet/validate-room.lua

# Inject service URLs and config into HTML pages if provided
# Sanitize: only allow safe characters (letters, digits, :, /, ., -, _)
RUN INJECT_SCRIPT=""; \
    sanitize_url() { echo "$1" | sed 's/[^a-zA-Z0-9:\/._-]//g'; }; \
    sanitize_key() { echo "$1" | sed 's/[^a-zA-Z0-9_-]//g'; }; \
    if [ -n "$MEETING_SERVICE_URL" ]; then \
        SAFE_URL=$(sanitize_url "$MEETING_SERVICE_URL"); \
        echo "Injecting MEETING_SERVICE_URL: $SAFE_URL"; \
        INJECT_SCRIPT="window.MEETING_SERVICE_URL='$SAFE_URL';"; \
    fi; \
    if [ -n "$AUTH_SERVICE_URL" ]; then \
        SAFE_URL=$(sanitize_url "$AUTH_SERVICE_URL"); \
        echo "Injecting AUTH_SERVICE_URL: $SAFE_URL"; \
        INJECT_SCRIPT="${INJECT_SCRIPT}window.AUTH_SERVICE_URL='$SAFE_URL';"; \
    fi; \
    if [ -n "$LEARNX_TOKEN_KEY" ]; then \
        SAFE_KEY=$(sanitize_key "$LEARNX_TOKEN_KEY"); \
        INJECT_SCRIPT="${INJECT_SCRIPT}window.LEARNX_TOKEN_KEY='$SAFE_KEY';"; \
    fi; \
    if [ -n "$LEARNX_REFRESH_KEY" ]; then \
        SAFE_KEY=$(sanitize_key "$LEARNX_REFRESH_KEY"); \
        INJECT_SCRIPT="${INJECT_SCRIPT}window.LEARNX_REFRESH_KEY='$SAFE_KEY';"; \
    fi; \
    if [ -n "$INJECT_SCRIPT" ]; then \
        sed -i "s|</head>|<script>${INJECT_SCRIPT}</script>\n</head>|" /usr/share/jitsi-meet/index.html; \
        sed -i "s|</head>|<script>${INJECT_SCRIPT}</script>\n</head>|" /usr/share/jitsi-meet/login.html; \
        sed -i "s|</head>|<script>${INJECT_SCRIPT}</script>\n</head>|" /usr/share/jitsi-meet/welcome.html; \
        sed -i "s|</head>|<script>${INJECT_SCRIPT}</script>\n</head>|" /usr/share/jitsi-meet/schedule.html; \
    fi

# Inject custom config, room validator, auth, and styles into index.html
# IMPORTANT: jitsi-room-validator.js must load BEFORE Jitsi app initializes
RUN sed -i 's|</head>|<script src="custom-config.js"></script>\n<script src="jitsi-room-validator.js"></script>\n<script src="jitsi-auth.js"></script>\n<link rel="stylesheet" href="css/custom-styles.css">\n</head>|' /usr/share/jitsi-meet/index.html

# Copy custom nginx config for serving LearnX HTML pages
# Jitsi's init script appends this to meet.conf at container startup
# Exact-match (=) locations take highest priority in nginx, so our
# login.html/error.html/welcome.html are served directly instead of
# being caught by the catch-all regex that rewrites to index.html
COPY custom-meet.conf /config/nginx/custom-meet.conf

# Set permissions
RUN chmod 644 /usr/share/jitsi-meet/custom-config.js && \
    chmod 644 /usr/share/jitsi-meet/jitsi-auth.js && \
    chmod 644 /usr/share/jitsi-meet/jitsi-room-validator.js && \
    chmod 644 /usr/share/jitsi-meet/login.html && \
    chmod 644 /usr/share/jitsi-meet/error.html && \
    chmod 644 /usr/share/jitsi-meet/welcome.html && \
    chmod 644 /usr/share/jitsi-meet/schedule.html && \
    chmod 644 /usr/share/jitsi-meet/index.html && \
    chmod 644 /usr/share/jitsi-meet/css/custom-styles.css && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-logo.svg && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-icon.svg && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-watermark.svg && \
    chmod 644 /usr/share/jitsi-meet/title.html && \
    chmod 644 /usr/share/jitsi-meet/manifest.json && \
    chmod 644 /usr/share/jitsi-meet/validate-room.lua
