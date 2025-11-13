## 🔧 Setup & Run
## NOTE RUN AS ROOT USER 
### Prerequisites
- Ubuntu 22.04 or newer | Sudo privileges | Git installed | Internet connection

### Installation
```bash
git clone https://github.com/EWANZO101/Simplistic-Node.git
cd Simplistic-Node
sudo chmod +x update_start.sh
./update_start.sh
```

### Service Management
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
