

---

# 🔧 **Simplistic-Node — Installation & Setup Guide**

> **Run all commands as `root` or with `sudo` privileges.**

---

## 📌 **Prerequisites**

Make sure your system meets the requirements:

* **OS:** Ubuntu 22.04 or newer
* **Git:** Installed (`git --version`)
* **Shell:** Bash or compatible
* **Privileges:** Sudo access
* **Network:** Active internet connection

---

# 🚀 **Installation Steps**

---

## **1️⃣ Clone the Repository**

```bash
git clone https://github.com/EWANZO101/Simplistic-Node.git
cd Simplistic-Node
```

---

## **2️⃣ Make the Update Script Executable**

```bash
sudo chmod +x update_start.sh
```

---

## **3️⃣ Run the Update / Start Script**

```bash
./update_start.sh
```

---

# ⚙️ **Service Management**

Use `systemctl` to manage the Simplistic-Node service.

> ⚠️ Replace **start-snaily-cadv4.service** with your actual service name if different.

---

### **Start Service**

```bash
sudo systemctl start start-snaily-cadv4.service
```

### **Restart Service**

```bash
sudo systemctl restart start-snaily-cadv4.service
```

### **Check Status**

```bash
sudo systemctl status start-snaily-cadv4.service
```

### **Stop Service**

```bash
sudo systemctl stop start-snaily-cadv4.service
```

---

# 🛠 **Troubleshooting**

Helpful commands for monitoring or debugging the service:

---

### **View Full Log File**

```bash
cat /home/snaily-cadv4/start.log
```

### **Monitor Log in Real-Time**

```bash
tail -f /home/snaily-cadv4/start.log
```

---

# 🆔 **Discord ID Setup**

Use the deployment script below to configure Discord-related settings.

---

### 📥 **Install & Run Deployment Script**

If you need help with this script, check the guide here:

[![qwick guide](https://raw.githubusercontent.com/EWANZO101/Simplistic-Node/main/qwick.png)](https://github.com/EWANZO101/Simplistic-Node/blob/main/qwick.md)

```bash
wget https://raw.githubusercontent.com/EWANZO101/Simplistic-Node/main/deploy-snailycad.sh
chmod +x deploy-snailycad.sh
./deploy-snailycad.sh
```

---
