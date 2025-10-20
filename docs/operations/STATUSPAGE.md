# Status Page Setup

## Why Separate Infrastructure?

**Golden Rule:** Never host your status page on the same infrastructure you're monitoring.

If your Kubernetes cluster goes down, your status page goes down with it → users have no way to know what's happening.

**Best Practice:**
- Different cloud provider (or at minimum, different region)
- Different DNS provider
- Separate domain (optional but recommended)

## Solution Comparison

| Feature | Upptime | Uptime Kuma |
|---------|---------|-------------|
| **Cost** | Free (GitHub) | $0-5/month (Fly.io/Railway) |
| **Infrastructure** | GitHub Actions + Pages | Self-hosted (separate) |
| **Setup Time** | 15 min | 30 min |
| **Maintenance** | Zero | Low |
| **Check Interval** | 5 minutes | 20-60 seconds |
| **Status Page UI** | Good | Excellent |
| **Protocols** | HTTP/HTTPS only | HTTP/HTTPS/TCP/DNS/Ping |
| **SSL Cert Monitoring** | ❌ | ✅ |
| **Incident Management** | GitHub Issues | Built-in |

**Recommendation:**
- **Staging:** Upptime (free, zero maintenance, 5min checks OK)
- **Production:** Uptime Kuma on Fly.io (faster checks, better UI, <$5/month)

---

## Option 1: Upptime (GitHub Pages)

### Setup

1. **Fork the template:**
   ```bash
   # Visit https://github.com/upptime/upptime
   # Click "Use this template" → Create new repository
   # Name: mycure-status (or similar)
   ```

2. **Configure `.upptimerc.yml`:**
   ```yaml
   owner: your-org
   repo: mycure-status
   
   sites:
     - name: Account App
       url: https://account.stg.mycureapp.com
     - name: API Health
       url: https://api.stg.mycureapp.com/health
     - name: HapiHub Health
       url: https://hapihub.stg.mycureapp.com/health
     - name: MyCure Frontend
       url: https://mycure.stg.mycureapp.com
     - name: Mailpit
       url: https://mail.stg.mycureapp.com
     - name: MinIO Health
       url: https://storage.stg.mycureapp.com/minio/health/live
   
   status-website:
     cname: status.stg.mycureapp.com
     name: MyCure Status
     introTitle: "Service Status"
     introMessage: Real-time status of MyCure services
   
   # Notifications (optional)
   notifications:
     - type: slack
       webhook: ${{ secrets.SLACK_WEBHOOK }}
   ```

3. **Custom Domain:**
   - Add DNS CNAME: `status.stg.mycureapp.com` → `your-org.github.io`
   - Enable GitHub Pages in repo settings
   - Wait for SSL cert provisioning (~5 min)

4. **Done!** GitHub Actions will run checks every 5 minutes.

---

## Option 2: Uptime Kuma (Fly.io)

### Setup

1. **Install Fly CLI:**
   ```bash
   curl -L https://fly.io/install.sh | sh
   fly auth signup  # or: fly auth login
   ```

2. **Create app:**
   ```bash
   mkdir uptime-kuma && cd uptime-kuma
   
   # Create fly.toml
   cat > fly.toml << 'EOF'
   app = "mycure-status"
   
   [build]
     image = "louislam/uptime-kuma:1"
   
   [env]
     UPTIME_KUMA_PORT = "3001"
   
   [http_service]
     internal_port = 3001
     force_https = true
     auto_start_machines = true
     auto_stop_machines = true
   
   [[http_service.checks]]
     interval = "15s"
     timeout = "10s"
     grace_period = "30s"
     method = "GET"
     path = "/"
   
   [[mounts]]
     source = "uptime_kuma_data"
     destination = "/app/data"
   EOF
   
   # Create volume
   fly volumes create uptime_kuma_data --size 1
   
   # Deploy
   fly deploy
   ```

3. **Custom domain:**
   ```bash
   fly certs add status.stg.mycureapp.com
   # Add DNS CNAME: status.stg.mycureapp.com → mycure-status.fly.dev
   ```

4. **Configure Uptime Kuma:**
   - Visit `https://status.stg.mycureapp.com`
   - Create admin account
   - Add monitors (same URLs as Upptime above)
   - Create public status page: Settings → Status Pages → Add
   - Set slug: `mycure-staging`
   - Publish it

5. **Notifications:**
   - Settings → Notifications
   - Add Slack/Discord/Email webhook

### Backup (Important!)

```bash
# Backup database
fly ssh console -C "cat /app/data/kuma.db" > kuma-backup-$(date +%Y%m%d).db

# Restore
fly ssh console
# Inside container: copy backup to /app/data/kuma.db
```

---

## MyCure Service Monitors

### Endpoints to Monitor

**Staging:**
- `https://account.stg.mycureapp.com` - Account App
- `https://api.stg.mycureapp.com/health` - API Health
- `https://hapihub.stg.mycureapp.com/health` - HapiHub Health  
- `https://mycure.stg.mycureapp.com` - MyCure Frontend
- `https://mail.stg.mycureapp.com` - Mailpit
- `https://storage.stg.mycureapp.com/minio/health/live` - MinIO

**Production** (when ready):
- `https://account.mycureapp.com`
- `https://api.mycureapp.com/health`
- etc.

### Check Configuration

**Upptime:**
- Interval: 5 minutes (fixed)
- Timeout: 30s
- Expected: 200 status code

**Uptime Kuma:**
- Interval: 60s (configurable)
- Timeout: 10s
- Retries: 3
- Expected: 200 status code
- SSL cert expiry: Alert 30 days before

---

## Operational Notes

### Adding a New Monitor
- **Upptime:** Edit `.upptimerc.yml`, commit, push
- **Uptime Kuma:** UI → Add New Monitor

### Posting an Incident
- **Upptime:** Manual GitHub Issue
- **Uptime Kuma:** UI → Incidents → Post New

### Maintenance Windows
- **Upptime:** Not supported (manual Issue)
- **Uptime Kuma:** UI → Maintenance → Schedule

### Cost Estimate
- **Upptime:** $0
- **Uptime Kuma (Fly.io):** $0-5/month (1GB volume + minimal compute)
