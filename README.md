## 🔧 Setup & Run (Git Install)

Follow these steps to automatically install and deploy your project using the latest **Node.js 22.x**, **pnpm**, and **PostgreSQL 16**.

### 🧾 Prerequisites
- Ubuntu 22.04 or newer  
- Sudo privileges  
- Git installed  
- Internet connection  

### 🚀 Quick Start
1. **Clone the repository**
   ```bash
   git clone https://github.com/EWANZO101/Simplistic-Node.git
   cd Simplistic-Node
   sudo chmod +x update_start.sh
   ./update_start.sh



#############################################
⚙️ Notes
🧠 What the Script Does & Doesn’t Do
✅ What It Does

Updates your system packages (apt update && apt upgrade) to keep everything current.

Installs dependencies automatically, including:

Node.js 22.x

pnpm

PostgreSQL 16

Git and Curl (if not installed)

Verifies environment variables, like DATABASE_URL and SECURE_COOKIES_FOR_IFRAME.

Pulls the latest code from your Git repository.

Installs Node dependencies using pnpm.

Runs database migrations to keep your schema up to date.

Starts or restarts your SnailyCAD (or project) service.

Logs actions and errors for easier debugging.

❌ What It Does Not Do

❌ It does not create your .env file — you need to configure your environment variables manually.

❌ It does not secure PostgreSQL (passwords, ports, etc.) — that’s up to you.

❌ It does not configure SSL or reverse proxies (like Nginx or Caddy).

❌ It does not repair custom code — if you’ve edited files, review changes before updating.

❌ It does not reboot your server automatically after updates.
