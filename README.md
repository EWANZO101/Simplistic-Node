## 🔧 Setup & Run
## NOTE RUN AS ROOT USER 
### Prerequisites
- Ubuntu 22.04 or newer | Sudo privileges | Git installed | Internet connection

# Simplistic-Node Installation Guide

Welcome to the **Simplistic-Node** setup guide. Follow the steps below to clone, set up, and run the project.

---

## Prerequisites

Before installing, make sure you have:

- Git installed (`git --version`)
- Bash or a compatible shell
- Sudo privileges (for permissions)

---

## Installation

### 1. Clone the repository

Open your terminal and run:

```bash
git clone https://github.com/EWANZO101/Simplistic-Node.git

cd Simplistic-Node


sudo chmod +x update_start.sh



./update_start.sh










### Service Management (Only after installed above )
```bash
# Start
sudo systemctl start start-snaily-cadv4.service

# Restart
sudo systemctl restart start-snaily-cadv4.service

# Status
sudo systemctl status start-snaily-cadv4.service

# Stop
sudo systemctl stop start-snaily-cadv4.service
```

### Troubleshooting
```bash
# View logs
cat /home/snaily-cadv4/start.log

# Monitor logs
tail -f /home/snaily-cadv4/start.log
```
