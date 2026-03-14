#!/bin/bash

# Jibri Finalize Recording Script
# After Jibri stops recording, this script:
#   1. Uploads the .mp4 to file-service (MinIO) via API gateway
#   2. Notifies meeting-service via webhook with file metadata
#
# Service URLs come from ENVIRONMENT VARIABLES (set in compose.yml)
# Room/session info comes from Jibri's metadata.json

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

# Check arguments (Jibri passes recording directory as $1)
if [ $# -lt 1 ]; then
    log "ERROR: No recording directory provided"
    exit 1
fi

RECORDING_DIR="$1"
log "Recording directory: $RECORDING_DIR"

if [ ! -d "$RECORDING_DIR" ]; then
    log "ERROR: Recording directory does not exist: $RECORDING_DIR"
    exit 1
fi

# ---- Configuration from environment variables (set in compose.yml) ----
# UPLOAD_SERVICE_URL = meeting-service webhook endpoint (e.g., http://host.docker.internal:2022/meeting-service/webhooks/jitsi)
# FILE_SERVICE_URL   = file-service base URL (e.g., http://host.docker.internal:2022/file-service)
# RECORDING_BUCKET   = MinIO bucket for recordings (default: recordings)
# JITSI_WEBHOOK_SECRET = shared secret for webhook authentication

FILE_SVC_URL="${FILE_SERVICE_URL:-}"
WEBHOOK_URL="${UPLOAD_SERVICE_URL:-}"
WEBHOOK_SECRET="${JITSI_WEBHOOK_SECRET:-}"
BUCKET="${RECORDING_BUCKET:-recordings}"

if [ -z "$FILE_SVC_URL" ]; then
    log "ERROR: FILE_SERVICE_URL environment variable not set"
    exit 1
fi

if [ -z "$WEBHOOK_URL" ]; then
    log "ERROR: UPLOAD_SERVICE_URL environment variable not set"
    exit 1
fi

# ---- Read room info from Jibri's metadata.json ----
METADATA_FILE="$RECORDING_DIR/metadata.json"
if [ ! -f "$METADATA_FILE" ]; then
    METADATA_FILE="/tmp/recordings/metadata.json"
fi

ROOM_NAME=""
if [ -f "$METADATA_FILE" ]; then
    log "Found metadata.json: $METADATA_FILE"
    ROOM_NAME=$(jq -r '.meeting_url // empty' "$METADATA_FILE" | sed 's|.*/||')
    if [ -z "$ROOM_NAME" ]; then
        ROOM_NAME=$(jq -r '.roomName // empty' "$METADATA_FILE")
    fi
    log "Room name from metadata: $ROOM_NAME"
else
    log "WARNING: metadata.json not found, extracting room name from directory"
fi

# Fallback: extract room name from directory path (e.g., /tmp/recordings/roomname_2024-01-01-12-00-00)
if [ -z "$ROOM_NAME" ]; then
    ROOM_NAME=$(basename "$RECORDING_DIR" | sed 's/_[0-9]\{4\}-[0-9]\{2\}-.*//')
    log "Room name from directory: $ROOM_NAME"
fi

# Generate unique session ID for this recording
SESSION_ID="rec_$(date '+%Y%m%d_%H%M%S')_$$"

log "Configuration:"
log "  Room: $ROOM_NAME"
log "  Session ID: $SESSION_ID"
log "  File Service: $FILE_SVC_URL"
log "  Webhook URL: $WEBHOOK_URL"
log "  Bucket: $BUCKET"

# ---- Find video file ----
VIDEO_FILE=$(find "$RECORDING_DIR" -name "*.mp4" -type f | head -n 1)

if [ -z "$VIDEO_FILE" ]; then
    log "ERROR: No .mp4 file found in $RECORDING_DIR"
    # Notify meeting-service about the failure
    if command -v jq &> /dev/null; then
        FAIL_PAYLOAD=$(jq -n \
            --arg roomName "$ROOM_NAME" \
            --arg sessionId "$SESSION_ID" \
            --arg reason "No video file produced" \
            '{
                eventType: "RECORDING_FAILED",
                roomName: $roomName,
                sessionId: $sessionId,
                reason: $reason,
                timestamp: now
            }')
        curl -X POST "${WEBHOOK_URL}/recording" \
            -H "Content-Type: application/json" \
            -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
            -d "$FAIL_PAYLOAD" \
            -s -o /dev/null || true
    fi
    exit 1
fi

log "Found video file: $VIDEO_FILE"

# ---- Get file info ----
FILE_SIZE=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || stat -f%z "$VIDEO_FILE" 2>/dev/null || echo "0")
FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc 2>/dev/null || echo "unknown")
log "File size: ${FILE_SIZE_MB} MB"

# ---- Upload to file-service (MinIO via API gateway) ----
STORAGE_PATH="/meetings/${ROOM_NAME}/${SESSION_ID}/"
UPLOAD_ENDPOINT="${FILE_SVC_URL}/files/upload"

log "Uploading to file-service: $UPLOAD_ENDPOINT"
log "  Storage path: $STORAGE_PATH"
log "  Bucket: $BUCKET"

UPLOAD_RESPONSE=$(curl -X POST "$UPLOAD_ENDPOINT" \
    -F "file=@${VIDEO_FILE};filename=$(basename "$VIDEO_FILE")" \
    -F "bucket=$BUCKET" \
    -F "path=$STORAGE_PATH" \
    -F "category=MEETING_RECORDINGS" \
    -F "referenceId=$ROOM_NAME" \
    -w "\n%{http_code}" \
    -s --max-time 300)

# Parse response
HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

log "Upload response (HTTP $HTTP_CODE):"
log "$RESPONSE_BODY"

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    log "ERROR: Upload failed with HTTP $HTTP_CODE"
    # Notify failure
    if command -v jq &> /dev/null; then
        FAIL_PAYLOAD=$(jq -n \
            --arg roomName "$ROOM_NAME" \
            --arg sessionId "$SESSION_ID" \
            --arg reason "Upload failed with HTTP $HTTP_CODE" \
            '{
                eventType: "RECORDING_FAILED",
                roomName: $roomName,
                sessionId: $sessionId,
                reason: $reason,
                timestamp: now
            }')
        curl -X POST "${WEBHOOK_URL}/recording" \
            -H "Content-Type: application/json" \
            -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
            -d "$FAIL_PAYLOAD" \
            -s -o /dev/null || true
    fi
    exit 1
fi

# Extract fileId from response
FILE_ID=$(echo "$RESPONSE_BODY" | jq -r '.fileId // .id // empty' 2>/dev/null)

if [ -z "$FILE_ID" ]; then
    log "WARNING: No fileId in upload response, using session ID"
    FILE_ID="$SESSION_ID"
fi

log "Upload successful, fileId: $FILE_ID"

# ---- Notify meeting-service via webhook ----
log "Sending recording_uploaded webhook..."

WEBHOOK_PAYLOAD=$(jq -n \
    --arg roomName "$ROOM_NAME" \
    --arg sessionId "$SESSION_ID" \
    --arg fileId "$FILE_ID" \
    --arg fileSize "$FILE_SIZE" \
    --arg storagePath "$STORAGE_PATH" \
    --arg bucket "$BUCKET" \
    '{
        eventType: "RECORDING_UPLOADED",
        roomName: $roomName,
        sessionId: $sessionId,
        fileId: $fileId,
        fileSize: ($fileSize | tonumber),
        storagePath: $storagePath,
        bucket: $bucket,
        timestamp: now
    }')

WEBHOOK_RESPONSE=$(curl -X POST "${WEBHOOK_URL}/recording" \
    -H "Content-Type: application/json" \
    -H "X-Webhook-Secret: $WEBHOOK_SECRET" \
    -d "$WEBHOOK_PAYLOAD" \
    -w "\n%{http_code}" \
    -s --max-time 30)

WEBHOOK_HTTP_CODE=$(echo "$WEBHOOK_RESPONSE" | tail -n 1)
WEBHOOK_BODY=$(echo "$WEBHOOK_RESPONSE" | sed '$d')

log "Webhook response (HTTP $WEBHOOK_HTTP_CODE):"
log "$WEBHOOK_BODY"

if [ "$WEBHOOK_HTTP_CODE" != "200" ] && [ "$WEBHOOK_HTTP_CODE" != "204" ]; then
    log "WARNING: Webhook notification failed (HTTP $WEBHOOK_HTTP_CODE), but upload succeeded"
fi

# ---- Cleanup local files ----
log "Cleaning up local recording files..."
rm -rf "$RECORDING_DIR"

log "Finalize script completed successfully"
log "========================================"

exit 0
