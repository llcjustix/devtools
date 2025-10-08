# Using official Jitsi Jibri image as base
FROM jitsi/jibri:stable-9258

# Fix repository issues and install dependencies for finalize script
RUN rm -f /etc/apt/sources.list.d/backports.list && \
    rm -f /etc/apt/sources.list.d/jitsi-stable.list && \
    echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bullseye-updates main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        jq \
        curl \
        bc \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy finalize script into image
COPY finalize-script.sh /usr/local/bin/jibri-finalize.sh

# Set executable permissions
RUN chmod +x /usr/local/bin/jibri-finalize.sh

# Create log directory
RUN mkdir -p /var/log/jibri && \
    chown jibri:jibri /var/log/jibri
