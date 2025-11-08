FROM jitsi/web:stable-9258

# Build argument for meeting service URL (optional, for production)
ARG MEETING_SERVICE_URL

# Copy custom config overrides (disable recording UI prompts, dynamic URLs)
COPY custom-config.js /usr/share/jitsi-meet/custom-config.js

# Copy custom CSS styles
COPY custom-styles.css /usr/share/jitsi-meet/css/custom-styles.css

# Copy LearnX logos
COPY images/learnx-logo.svg /usr/share/jitsi-meet/images/learnx-logo.svg
COPY images/learnx-watermark.svg /usr/share/jitsi-meet/images/learnx-watermark.svg

# Copy custom branding files
COPY title.html /usr/share/jitsi-meet/title.html
COPY manifest.json /usr/share/jitsi-meet/manifest.json

# Copy authentication and validation files
COPY jitsi-auth.js /usr/share/jitsi-meet/jitsi-auth.js
COPY jitsi-room-validator.js /usr/share/jitsi-meet/jitsi-room-validator.js
COPY login.html /usr/share/jitsi-meet/login.html
COPY error.html /usr/share/jitsi-meet/error.html

# Inject meeting service URL into HTML if provided (makes it available to JavaScript)
# This allows production deployments to override the URL detection logic
RUN if [ -n "$MEETING_SERVICE_URL" ]; then \
        echo "Injecting MEETING_SERVICE_URL: $MEETING_SERVICE_URL"; \
        sed -i "s|</head>|<script>window.MEETING_SERVICE_URL='$MEETING_SERVICE_URL';</script>\n</head>|" /usr/share/jitsi-meet/index.html; \
    else \
        echo "No MEETING_SERVICE_URL provided - will use auto-detection"; \
    fi

# Inject custom config, room validator, auth, and styles into index.html
# IMPORTANT: jitsi-room-validator.js must load BEFORE Jitsi app initializes
RUN sed -i 's|</head>|<script src="custom-config.js"></script>\n<script src="jitsi-room-validator.js"></script>\n<script src="jitsi-auth.js"></script>\n<link rel="stylesheet" href="css/custom-styles.css">\n</head>|' /usr/share/jitsi-meet/index.html

# Set permissions
RUN chmod 644 /usr/share/jitsi-meet/custom-config.js && \
    chmod 644 /usr/share/jitsi-meet/jitsi-auth.js && \
    chmod 644 /usr/share/jitsi-meet/jitsi-room-validator.js && \
    chmod 644 /usr/share/jitsi-meet/login.html && \
    chmod 644 /usr/share/jitsi-meet/error.html && \
    chmod 644 /usr/share/jitsi-meet/index.html && \
    chmod 644 /usr/share/jitsi-meet/css/custom-styles.css && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-logo.svg && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-watermark.svg && \
    chmod 644 /usr/share/jitsi-meet/title.html && \
    chmod 644 /usr/share/jitsi-meet/manifest.json
