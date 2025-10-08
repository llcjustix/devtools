#!/bin/bash

# Jibri Finalize Recording Script
# Uploads recordings to file-service and notifies meeting-service
# All configuration from metadata.json (zero hardcoding)

set -e

# Logging
LOG_FILE="/var/log/jibri/finalize.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================"
log "Finalize script started"
log "Arguments: $*"

# Check arguments
if [ $# -lt 1 ]; then
    log "ERROR: No recording directory provided"
    exit 1
fi

RECORDING_DIR="$1"
log "Recording directory: $RECORDING_DIR"

# Verify directory exists
if [ ! -d "$RECORDING_DIR" ]; then
    log "ERROR: Recording directory does not exist: $RECORDING_DIR"
    exit 1
fi

# Find metadata.json
METADATA_FILE="$RECORDING_DIR/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
    # Try parent directory (/tmp/recordings)
    METADATA_FILE="/tmp/recordings/metadata.json"
fi

if [ ! -f "$METADATA_FILE" ]; then
    log "ERROR: metadata.json not found in $RECORDING_DIR or /tmp/recordings"
    exit 1
fi

log "Found metadata.json: $METADATA_FILE"

# Read configuration from metadata.json (ZERO HARDCODING)
ROOM_NAME=$(jq -r '.roomName // empty' "$METADATA_FILE")
MEETING_ID=$(jq -r '.meetingId // empty' "$METADATA_FILE")
SESSION_ID=$(jq -r '.sessionId // empty' "$METADATA_FILE")
FILE_SERVICE_URL=$(jq -r '.recordingUploadConfig.fileServiceUrl // empty' "$METADATA_FILE")
UPLOAD_PATH=$(jq -r '.recordingUploadConfig.uploadPath // empty' "$METADATA_FILE")
BUCKET=$(jq -r '.recordingUploadConfig.bucket // empty' "$METADATA_FILE")
STORAGE_PATH=$(jq -r '.recordingUploadConfig.storagePath // empty' "$METADATA_FILE")
WEBHOOK_URL=$(jq -r '.recordingUploadConfig.webhookUrl // empty' "$METADATA_FILE")
WEBHOOK_SECRET=$(jq -r '.recordingUploadConfig.webhookSecret // empty' "$METADATA_FILE")

log "Configuration loaded:"
log "  Room: $ROOM_NAME"
log "  Meeting ID: $MEETING_ID"
log "  Session ID: $SESSION_ID"
log "  File Service: $FILE_SERVICE_URL"
log "  Upload Path: $UPLOAD_PATH"
log "  Bucket: $BUCKET"
log "  Storage Path: $STORAGE_PATH"
log "  Webhook URL: $WEBHOOK_URL"

# Validate configuration
if [ -z "$FILE_SERVICE_URL" ] || [ -z "$WEBHOOK_URL" ]; then
    log "ERROR: Missing required configuration in metadata.json"
    exit 1
fi

# Find video file
VIDEO_FILE=$(find "$RECORDING_DIR" -name "*.mp4" -type f | head -n 1)

if [ -z "$VIDEO_FILE" ]; then
    log "ERROR: No .mp4 file found in $RECORDING_DIR"
    exit 1
fi

log "Found video file: $VIDEO_FILE"

# Get file info
FILE_SIZE=$(stat -f%z "$VIDEO_FILE" 2>/dev/null || stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
log "File size: $FILE_SIZE_MB MB"

# Upload to file-service
log "Uploading to file-service..."

UPLOAD_RESPONSE=$(curl -X POST "$FILE_SERVICE_URL$UPLOAD_PATH" \
    -F "file=@$VIDEO_FILE;filename=$(basename "$VIDEO_FILE")" \
    -F "bucket=$BUCKET" \
    -F "path=$STORAGE_PATH" \
    -F "metadata={\"roomName\":\"$ROOM_NAME\",\"meetingId\":\"$MEETING_ID\",\"sessionId\":\"$SESSION_ID\"}" \
    -w "\n%{http_code}" \
    -s)

# Parse response
HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$UPLOAD_RESPONSE" | head -n -1)

log "Upload response (HTTP $HTTP_CODE):"
log "$RESPONSE_BODY"

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    log "ERROR: Upload failed with HTTP $HTTP_CODE"
    exit 1
fi

# Extract fileId from response
FILE_ID=$(echo "$RESPONSE_BODY" | jq -r '.fileId // .id // empty')

if [ -z "$FILE_ID" ]; then
    log "ERROR: No fileId in upload response"
    exit 1
fi

log "Upload successful, fileId: $FILE_ID"

# Calculate duration (rough estimate from file size - 1MB ≈ 1 minute for typical quality)
DURATION_SECONDS=$(echo "scale=0; $FILE_SIZE / 1048576 * 60" | bc)
log "Estimated duration: $DURATION_SECONDS seconds"

# Notify meeting-service via webhook
log "Sending webhook to meeting-service..."

WEBHOOK_PAYLOAD=$(jq -n \
    --arg roomName "$ROOM_NAME" \
    --arg status "stopped" \
    --arg sessionId "$SESSION_ID" \
    --arg meetingId "$MEETING_ID" \
    --arg fileId "$FILE_ID" \
    --arg fileSize "$FILE_SIZE" \
    --arg duration "$DURATION_SECONDS" \
    '{
        roomName: $roomName,
        status: $status,
        sessionId: $sessionId,
        meetingId: $meetingId,
        fileId: $fileId,
        fileSize: ($fileSize | tonumber),
        durationSeconds: ($duration | tonumber),
        timestamp: now
    }')

WEBHOOK_RESPONSE=$(curl -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
    -d "$WEBHOOK_PAYLOAD" \
    -w "\n%{http_code}" \
    -s)

WEBHOOK_HTTP_CODE=$(echo "$WEBHOOK_RESPONSE" | tail -n 1)
WEBHOOK_BODY=$(echo "$WEBHOOK_RESPONSE" | head -n -1)

log "Webhook response (HTTP $WEBHOOK_HTTP_CODE):"
log "$WEBHOOK_BODY"

if [ "$WEBHOOK_HTTP_CODE" != "200" ] && [ "$WEBHOOK_HTTP_CODE" != "204" ]; then
    log "WARNING: Webhook failed with HTTP $WEBHOOK_HTTP_CODE (upload succeeded)"
fi

# Cleanup local files
log "Cleaning up local files..."
rm -rf "$RECORDING_DIR"
rm -f "$METADATA_FILE"

log "Finalize script completed successfully"
log "========================================"

exit 0
