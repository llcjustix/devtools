# 🚀 JustIX Academy Infrastructure

This repository contains the **Docker Compose setup** for the **JustIX Academy** platform infrastructure.  
It provides a complete local development stack with databases, identity management, caching, object storage, messaging, and UI tools.


---

## Overview

The stack includes essential services such as:

- 🐘 PostgreSQL (with schema initialization support)
- 🔐 Keycloak (identity and access management)
- 🧠 Redis + Redis Insight UI (for visualization)
- ☁️ MinIO (S3-compatible object storage)
- 📨 Apache Kafka + Kafka UI (for messaging and debugging)
- 🔄 Health checks and persistent volumes
- 📦 Full environment variable customization

> ✅ All services are pre-configured with sensible defaults and ready for local development.

---


---

## 📚 Services

| Service    | Description                    | Ports                 |
|------------|--------------------------------|------------------------|
| PostgreSQL | Relational Database            | `5432`                |
| Keycloak   | Identity and Access Management | `8080`                |
| Redis      | In-Memory Data Store           | `6379`                |
| MinIO      | S3-Compatible Object Storage   | `9000` (API), `9001` (Console) |
| Kafka      | Distributed Messaging System   | `9092`, `29092`       |
| Kafka UI   | Web UI for managing Kafka      | `8000`                |
| Redis UI   | Web UI for managing Redis      | `5540`                |

---

## 🗃️ Database Initialization

- PostgreSQL automatically loads SQL schema from `./db/schema.sql`.
- Keycloak uses its own schema (`KC_DB_SCHEMA=keycloak`) inside the same database.
- The `keycloak-init` container disables SSL enforcement in Keycloak’s `master` realm automatically at startup.

---

### 2. ⚙️ Environment Variables

Create a `.env` file in the root directory to override default credentials and settings.

## 🛠️ Getting Started

### 1. 📦 Prerequisites

- Docker `v28.0.4+`
- Docker Compose `v2.34.0+`

---

## 🛠 Usage

### ✅ Requirements

- Docker
- Docker Compose

---

### ▶️ Start All Services

``` bash
    docker compose up -d
```
### ▶️ Stop All Services

``` bash
    docker compose down
```
### ▶️ View Logs
``` bash
    docker compose logs -f
```

