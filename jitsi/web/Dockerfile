FROM jitsi/web:stable-9258

# Copy custom interface config (branding, colors, UI customization)
COPY interface_config.js /defaults/interface_config.js

# Copy custom config overrides (disable recording UI prompts)
COPY custom-config.js /usr/share/jitsi-meet/custom-config.js

# Copy custom CSS styles
COPY custom-styles.css /usr/share/jitsi-meet/css/custom-styles.css

# Copy LearnX logos
COPY images/learnx-logo.svg /usr/share/jitsi-meet/images/learnx-logo.svg
COPY images/learnx-watermark.svg /usr/share/jitsi-meet/images/learnx-watermark.svg

# Inject custom config and styles into index.html
# This ensures custom-config.js loads after main config.js
RUN sed -i 's|</head>|<script src="custom-config.js"></script>\n<link rel="stylesheet" href="css/custom-styles.css">\n</head>|' /usr/share/jitsi-meet/index.html

# Set permissions
RUN chmod 644 /defaults/interface_config.js && \
    chmod 644 /usr/share/jitsi-meet/custom-config.js && \
    chmod 644 /usr/share/jitsi-meet/css/custom-styles.css && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-logo.svg && \
    chmod 644 /usr/share/jitsi-meet/images/learnx-watermark.svg
