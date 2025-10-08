# 🚀 JustIX Academy Infrastructure

This repository contains the **Docker Compose setup** for the **JustIX Academy** platform infrastructure.
It provides a complete local development stack with databases, identity management, caching, object storage, messaging, and video conferencing.

---

## 📚 Table of Contents

- [Overview](#overview)
- [Services](#services)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Jitsi Meet Setup](#jitsi-meet-setup)
- [Network Configuration](#network-configuration)
- [Database Initialization](#database-initialization)
- [Troubleshooting](#troubleshooting)

---

## Overview

The stack includes essential services for modern application development:

- 🐘 **PostgreSQL** - Relational database with schema initialization
- 🔐 **Keycloak** - Identity and access management
- 🧠 **Redis** + **Redis Insight** - In-memory cache with web UI
- ☁️ **MinIO** - S3-compatible object storage
- 📨 **Apache Kafka** + **Kafka UI** - Event streaming platform
- 🎥 **Jitsi Meet** - Self-hosted video conferencing with recording
- 🔄 **Health checks** - Automatic service monitoring
- 📦 **Persistent volumes** - Data preservation across restarts

> ✅ All services are pre-configured with sensible defaults and ready for local development.

---

## 📚 Services

| Service | Description | Ports | Access |
|---------|-------------|-------|--------|
| **PostgreSQL** | Relational Database | `5432` | `postgresql://postgres:passwd@localhost:5432/academy` |
| **Keycloak** | Identity Management | `8080` | http://localhost:8080 (admin/admin) |
| **Redis** | In-Memory Data Store | `6379` | `redis://localhost:6379` (passwd: `passwd`) |
| **Redis Insight** | Redis Web UI | `5540` | http://localhost:5540 |
| **MinIO** | Object Storage | `9000`, `9001` | Console: http://localhost:9001 (minio/minio123) |
| **Kafka** | Messaging System | `9092`, `29092` | Bootstrap: `localhost:9092` |
| **Kafka UI** | Kafka Web UI | `8000` | http://localhost:8000 |
| **Jitsi Meet** | Video Conferencing | `8443` | http://10.1.0.160:8443 (see [Network Config](#network-configuration)) |
| **Jitsi Prosody** | XMPP Server | Internal | N/A |
| **Jitsi Jicofo** | Conference Focus | Internal | N/A |
| **Jitsi JVB** | Video Bridge | `10000/udp` | N/A |
| **Jitsi Jibri** | Recording Service | Internal | Recordings: `./data/jitsi-recordings/` |

---

## 🛠️ Prerequisites

- **Docker** `v28.0.4+`
- **Docker Compose** `v2.34.0+`
- At least **4GB** of available RAM
- At least **10GB** of free disk space

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd devtools
```

### 2. Start All Services

```bash
docker compose up -d
```

### 3. Verify Services

```bash
docker compose ps
```

All services should show as "Up" or "healthy".

### 4. Access Services

- **Keycloak**: http://localhost:8080 (admin/admin)
- **Redis Insight**: http://localhost:5540
- **MinIO Console**: http://localhost:9001 (minio/minio123)
- **Kafka UI**: http://localhost:8000
- **Jitsi Meet**: http://10.1.0.160:8443 (replace with your LAN IP)

### 5. Stop Services

```bash
docker compose down
```

To remove volumes (⚠️ deletes all data):
```bash
docker compose down -v
```

---

## 🎥 Jitsi Meet Setup

Jitsi Meet is a self-hosted video conferencing platform integrated into this stack.

### Quick Access

- **Local Machine Only**: http://localhost:8443
- **Multi-User/LAN Access**: http://10.1.0.160:8443 (replace `10.1.0.160` with your actual LAN IP)

### Architecture

The Jitsi stack consists of:

1. **jitsi-web** - Web frontend (Nginx + React)
2. **jitsi-prosody** - XMPP server for signaling
3. **jitsi-jicofo** - Conference focus (manages meetings)
4. **jitsi-jvb** - Video bridge (streams media)
5. **jitsi-jibri** - Recording service (optional)

### Features

✅ **Guest Access** - No authentication required by default
✅ **Recording** - Jibri service for recording meetings
✅ **Custom Modules** - Prosody webhook integration
✅ **Multi-User Support** - Proper network configuration for LAN access
✅ **Health Monitoring** - All services have health checks

### Custom Docker Images

Jitsi uses **custom Docker images** with baked-in webhook module and finalize script:

```
jitsi/
├── prosody/
│   ├── Dockerfile                        # Custom Prosody build
│   └── mod_jitsi_webhooks_enhanced.lua   # Webhook module (baked in)
└── jibri/
    ├── Dockerfile                        # Custom Jibri build
    └── finalize-script.sh                # Recording upload script (baked in)
```

No configuration files to manage - everything is baked into the images!

### Environment Variables

Key Jitsi settings in `.env`:

```bash
# Public URL - IMPORTANT for multi-user access
PUBLIC_URL=10.1.0.160:8443  # Use your LAN IP, not localhost

# Authentication (disabled for development)
ENABLE_AUTH=0
ENABLE_GUESTS=1

# Recording
ENABLE_RECORDING=1

# HTTPS (disabled for local development)
DISABLE_HTTPS=1

# Jibri Recording Credentials
JIBRI_RECORDER_USER=recorder
JIBRI_RECORDER_PASSWORD=<auto-generated>
JIBRI_XMPP_USER=jibri
JIBRI_XMPP_PASSWORD=<auto-generated>

# Jicofo Credentials
JICOFO_COMPONENT_SECRET=<auto-generated>
JICOFO_AUTH_PASSWORD=<auto-generated>

# JVB Credentials
JVB_AUTH_PASSWORD=<auto-generated>
```

### Custom Images (Oracle Pattern)

Jitsi uses custom Docker images with baked-in customizations, following the same pattern as `~/IdeaProjects/i/datarepo/oracle-database-enterprise/`:

**Structure:**
```
jitsi/
├── prosody/
│   ├── Dockerfile                        # Custom Prosody image
│   └── mod_jitsi_webhooks_enhanced.lua   # Webhook module (baked in)
├── jibri/
│   ├── Dockerfile                        # Custom Jibri image
│   └── finalize-script.sh                # Upload script (baked in)
└── web/
    ├── Dockerfile                        # Custom Web UI image
    ├── interface_config.js               # Branding customization (baked in)
    ├── custom-config.js                  # Recording & feature config (baked in)
    └── custom-styles.css                 # Design customization (baked in)
```

**Prosody (justix/jitsi-prosody:latest):**
- FROM jitsi/prosody:stable-9258
- Installs Lua dependencies
- Copies mod_jitsi_webhooks_enhanced.lua into image
- Sends 7 webhooks + creates metadata.json for recordings

**Jibri (justix/jitsi-jibri:latest):**
- FROM jitsi/jibri:stable-9258
- Installs dependencies (jq, curl, bc)
- Copies finalize-script.sh into image
- Automatically uploads recordings to file-service

**Web (justix/jitsi-web:latest):**
- FROM jitsi/web:stable-9258
- Customizes branding (interface_config.js): JustIX Academy branding, custom colors
- Disables recording UI prompts (custom-config.js): Uses backend logic only
- Applies custom design (custom-styles.css): Blue theme, custom buttons/colors
- Injects RoomConfiguration from backend: Dynamic feature control per meeting

**Building custom images:**
```bash
docker-compose -f compose.yml build jitsi-prosody
docker-compose -f compose.yml build jitsi-jibri
docker-compose -f compose.yml build jitsi-web
```

**Updating customizations:**
```bash
# Edit files
nano jitsi/prosody/mod_jitsi_webhooks_enhanced.lua
nano jitsi/jibri/finalize-script.sh
nano jitsi/web/interface_config.js
nano jitsi/web/custom-config.js
nano jitsi/web/custom-styles.css

# Rebuild and recreate
docker-compose -f compose.yml build jitsi-prosody jitsi-jibri jitsi-web
docker-compose -f compose.yml up -d --force-recreate jitsi-prosody jitsi-jibri jitsi-web
```

**Benefits:**
- ✅ Immutable images - Customizations baked in
- ✅ No volume mounts - Faster, cleaner
- ✅ Production ready - Push to registry
- ✅ Same pattern as Oracle image customization

---

## 🌐 Network Configuration

### Single User (localhost)

For testing on a single machine:

```bash
# In .env
PUBLIC_URL=localhost:8443
```

Access at: http://localhost:8443

### Multiple Users (LAN)

For multiple users on the same network:

#### Step 1: Find Your LAN IP

**macOS/Linux:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

**Windows:**
```cmd
ipconfig
```

Example output: `10.1.0.160`

#### Step 2: Update Public URL

**Option A: Using the helper script (recommended):**

```bash
./update-public-url.sh 10.1.0.160:8443
```

This script automatically:
- Updates `PUBLIC_URL` in `.env`
- Updates BOSH/WebSocket URLs in `jitsi/web/config.js`
- Restarts Jitsi services

**Option B: Manual update:**

```bash
# 1. Update .env
PUBLIC_URL=10.1.0.160:8443  # Replace with your actual IP

# 2. Make config.js writable
chmod 644 jitsi/web/config.js

# 3. Edit the file - update these lines:
# config.bosh = 'http://10.1.0.160:8443/' + subdir + 'http-bind';
# config.websocket = 'ws://10.1.0.160:8443/' + subdir + 'xmpp-websocket';

# 4. Make read-only again
chmod 444 jitsi/web/config.js
```

#### Step 3: Access Jitsi

All users should now access: **http://10.1.0.160:8443** (replace with your IP)

### Firewall Configuration

Ensure these ports are open:

- **TCP 8443** - Jitsi web interface
- **UDP 10000** - JVB media streams (video/audio)

**macOS:**
```bash
# Firewall settings in System Preferences > Security & Privacy
```

**Linux (ufw):**
```bash
sudo ufw allow 8443/tcp
sudo ufw allow 10000/udp
```

---

## 🗃️ Database Initialization

### PostgreSQL

- **Auto-initialization**: SQL schema loaded from `./db/schema.sql` on first start
- **Keycloak schema**: Stored in separate schema (`keycloak`) within the same database
- **Connection**: `postgresql://postgres:passwd@localhost:5432/academy`

### Keycloak

- **Admin credentials**: admin/admin (configured via `KC_BOOTSTRAP_ADMIN_*` env vars)
- **SSL disabled**: The `keycloak-init` service automatically disables SSL requirement for the `master` realm
- **Database**: Uses PostgreSQL with `keycloak` schema

### Data Persistence

All data is stored in `./data/`:

```
data/
├── postgres/           # PostgreSQL data
├── redis/             # Redis data
├── minio/             # Object storage
├── kafka/             # Kafka logs
└── jitsi-recordings/  # Jibri recordings
```

---

## 🔧 Troubleshooting

### Jitsi: "You have been disconnected"

**Symptom**: Users immediately disconnected after joining

**Causes & Solutions:**

1. **Wrong network configuration**
   - **Fix**: Update `PUBLIC_URL` in `.env` to your LAN IP (not `localhost`)
   - **Fix**: Update `config.bosh` and `config.websocket` in `jitsi-config/web/config.js`

2. **JVB not joined brewery MUC**
   - **Check**: `docker logs devtools-jitsi-jvb-1 | grep "Joined MUC"`
   - **Should see**: `Joined MUC: jvbbrewery@internal-muc.meet.jitsi`
   - **Fix**: Ensure `JVB_BREWERY_MUC=jvbbrewery` (not `jvbbrewery@internal-muc.meet.jitsi`)

3. **Prosody hostname mismatch**
   - **Check**: `docker logs devtools-jitsi-web-1 | grep prosody`
   - **Fix**: Ensure all services use `jitsi-prosody` not `prosody` in depends_on and XMPP_SERVER

4. **HTTPS/WSS protocol mismatch**
   - **Check**: `jitsi/web/config.js` should use `http://` and `ws://` (not `https://` or `wss://`)
   - **Fix**: Set `DISABLE_HTTPS=1` in `.env` and update config.js manually

### Services Not Starting

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f <service-name>

# Restart specific service
docker compose restart <service-name>

# Recreate service
docker compose up -d --force-recreate <service-name>
```

### Port Conflicts

If ports are already in use:

```bash
# Check what's using a port
lsof -i :8080  # macOS/Linux
netstat -ano | findstr :8080  # Windows

# Change port in compose.yml
# Example: Change Keycloak from 8080 to 8081
ports:
  - "8081:8080"
```

### Reset Everything

```bash
# Stop and remove all containers, networks, and volumes
docker compose down -v

# Remove data (⚠️ deletes all data)
rm -rf data/

# Start fresh
docker compose up -d
```

### Check Service Health

```bash
# View health status
docker compose ps

# Check specific service health
docker inspect devtools-jitsi-jvb-1 | grep -A10 Health
```

---

## 🎨 Customization & Branding

You can fully customize Jitsi Meet's appearance including logos, colors, and layout.

### Quick Branding Setup

1. **Add your logos** to `jitsi/web/branding/images/`:
   - `logo.svg` - Main logo (welcome page)
   - `logo-small.svg` - Small logo (meeting toolbar)
   - `favicon.ico` - Browser tab icon

2. **Edit** `jitsi/web/interface_config.js`:
   ```javascript
   APP_NAME: 'Your Company Name'
   PROVIDER_NAME: 'Your Company'
   DEFAULT_WELCOME_PAGE_LOGO_URL: 'images/your-logo.svg'
   DEFAULT_BACKGROUND: '#your-color'
   ```

3. **Add custom CSS** (optional) in `jitsi/web/branding/css/custom-styles.css`

4. **Restart Jitsi**:
   ```bash
   docker compose restart jitsi-web
   ```

📚 **Full Guide**: See `jitsi/web/branding/README.md` for complete customization options

---

## 📖 Additional Documentation

For detailed information about specific components:

- **Branding & Customization**: See `jitsi/web/branding/README.md` for logo, colors, and layout customization
- **Jitsi Webhooks**: See `jitsi/prosody/modules/` for webhook integration
- **Recording Setup**: See `jitsi/jibri/scripts/` for recording configuration
- **Authentication Flow**: JWT token handling between services
- **Meeting Service**: Integration with backend for room validation

---

## 🔒 Security Notes

### Development vs Production

This setup is configured for **local development**:

- ⚠️ **Default passwords** - Change all credentials in production
- ⚠️ **No SSL/TLS** - Enable HTTPS for production
- ⚠️ **Guest access enabled** - Configure authentication for production
- ⚠️ **Exposed ports** - Use reverse proxy (Nginx/Traefik) in production

### Production Checklist

- [ ] Generate strong passwords for all services
- [ ] Enable SSL/TLS (`DISABLE_HTTPS=0`)
- [ ] Configure JWT authentication (`ENABLE_AUTH=1`)
- [ ] Set up proper firewall rules
- [ ] Use Docker secrets for sensitive data
- [ ] Configure backup strategy
- [ ] Set up monitoring and logging
- [ ] Use proper domain names (not IP addresses)

---

## 📝 Version Information

- **Docker**: 28.0.4+
- **Docker Compose**: 2.34.0+
- **Jitsi**: stable-9258
- **PostgreSQL**: latest
- **Keycloak**: latest
- **Redis**: latest
- **MinIO**: latest
- **Kafka**: latest (Confluent Platform)

---

## 🤝 Contributing

When making changes to the infrastructure:

1. Test locally with `docker compose up -d`
2. Verify all services are healthy
3. Update this README if configuration changes
4. Document any new environment variables
5. Test multi-user scenarios for Jitsi changes

---

## 📄 License

[Your License Here]
