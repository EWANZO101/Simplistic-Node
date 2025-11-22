# 🚀 SnailyCAD Auto-Deploy Script - Simple Guide

## 📌 What Does This Script Do?

This script **automatically deploys and updates** your SnailyCAD server with one command. No more manual steps!

### It Handles Everything:
✅ Backs up your current setup (just in case)  
✅ Asks for your Discord & Steam API keys  
✅ Downloads the latest SnailyCAD code from GitHub  
✅ Installs all needed files and updates  
✅ Builds the project  
✅ Sets up auto-start service (runs on boot)  
✅ Starts SnailyCAD automatically  

**Before this script**: 15+ manual steps, easy to mess up  
**With this script**: Answer a few questions, done in 3 minutes ✨

---

## 🎯 How to Use It (Super Simple)

### Step 1: Download the Script
```bash
cd /home/snaily-cadv4
wget https://raw.githubusercontent.com/EWANZO101/Simplistic-Node/main/deploy-snailycad.sh
chmod +x deploy-snailycad.sh
```

### Step 2: Run It
```bash
./deploy-snailycad.sh
```

### Step 3: Answer the Questions
The script will ask you for:
- **Discord Bot Token** - Get it from [Discord Developer Portal](https://discord.com/developers/applications)
- **Discord Server ID** - Right-click your server → Copy ID
- **Discord Client ID & Secret** - From Discord Developer Portal
- **Steam API Key** - Get it from [Steam](https://steamcommunity.com/dev/apikey)

Just paste them in (no quotes needed - the script adds them automatically).

### Step 4: Wait
The script does everything automatically:
- Creates a backup ✅
- Downloads latest updates ✅
- Builds the project ✅
- Starts the service ✅

**Done!** Your SnailyCAD is running! 🎉

---

## 💡 What You'll See

```bash
╔═══════════════════════════════════════════════════════════════╗
║           SnailyCAD Professional Deployment Tool              ║
║                        Version 2.0                            ║
╚═══════════════════════════════════════════════════════════════╝

[✓] git is installed
[✓] node is installed
[✓] pnpm is installed
[INFO] Node version: v18.17.0
[*] Creating backup...
[✓] Backup created: backups/backup_20250122_143052.tar.gz

DISCORD_BOT_TOKEN
Paste the raw value (no quotes - they will be added automatically)
Enter value [current: none]: YOUR_TOKEN_HERE

... (continues with all questions)

[✓] Environment file updated
[*] Fetching latest code...
[✓] Repository updated to latest commit
[*] Installing dependencies...
[✓] Dependencies installed
[*] Building project...
[✓] Build completed in 67 seconds
[✓] Service started successfully

╔═══════════════════════════════════════════════════════════════╗
║                  DEPLOYMENT COMPLETED ✓                       ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## 🔄 Common Tasks

### Update SnailyCAD to Latest Version
```bash
./deploy-snailycad.sh
```
That's it! Same command updates everything.

### Check if SnailyCAD is Running
```bash
sudo systemctl status start-snaily-cadv4.service
```

### View Live Logs
```bash
sudo journalctl -u start-snaily-cadv4.service -f
```

### Restart SnailyCAD
```bash
sudo systemctl restart start-snaily-cadv4.service
```

### Stop SnailyCAD
```bash
sudo systemctl stop start-snaily-cadv4.service
```

---

## ❓ Quick Troubleshooting

### "Service failed to start"
```bash
# Check what went wrong:
sudo journalctl -u start-snaily-cadv4.service -n 50

# Common fix - wrong API keys:
nano /home/snaily-cadv4/.env
# Fix your keys, then:
sudo systemctl restart start-snaily-cadv4.service
```

### "Script says another deployment is running"
```bash
# Remove the lock file:
rm -f /var/lock/snailycad-deploy.lock
# Try again:
./deploy-snailycad.sh
```

### "Wrong Discord/Steam keys"
```bash
# Edit the .env file:
nano /home/snaily-cadv4/.env
# Fix the values, save (CTRL+S), exit (CTRL+X)
# Restart:
sudo systemctl restart start-snaily-cadv4.service
```

---

## 🛡️ Safety Features

This script is **production-ready** and won't break your server:

✅ **Creates backups** before making any changes  
✅ **Validates your inputs** to catch mistakes  
✅ **Checks disk space** before starting  
✅ **Shows you what it's doing** at every step  
✅ **Keeps 5 backups** automatically (rotates old ones)  
✅ **Can recover** if something goes wrong  

---

## 📱 Help & Support

- **Full Documentation**: See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **SnailyCAD Docs**: https://docs.snailycad.org/
- **SnailyCAD Discord**: https://discord.gg/eGnrPqEH7U
- **Issues**: https://github.com/EWANZO101/Simplistic-Node/issues

---

## ⚡ Quick Facts

| Question | Answer |
|----------|--------|
| **Time to deploy?** | 3-5 minutes |
| **Breaks my server?** | No - creates backups first |
| **Need to know Linux?** | Nope - just paste your API keys |
| **Works on updates?** | Yes - same command updates everything |
| **Auto-starts on reboot?** | Yes - systemd service included |
| **Free?** | 100% free and open source |

---

## 🎬 TL;DR (Too Long; Didn't Read)

```bash
# 1. Download
wget https://raw.githubusercontent.com/EWANZO101/Simplistic-Node/main/deploy-snailycad.sh
chmod +x deploy-snailycad.sh

# 2. Run
./deploy-snailycad.sh

# 3. Enter your Discord & Steam keys when asked

# 4. Done! SnailyCAD is running 🎉
```

**That's literally it.** The script does everything else for you!

---

**Made by the community, for the community** ❤️  
*Star the repo if this helped you!* ⭐
