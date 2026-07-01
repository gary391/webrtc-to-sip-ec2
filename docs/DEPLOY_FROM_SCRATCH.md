# Deploying WebRTC-to-SIP from Scratch

This guide lists every single command required to deploy the WebRTC-to-SIP gateway on a fresh AWS EC2 Debian 13 instance from scratch.

---

## Phase 1: Launch Infrastructure

### Step 1.1: Deploy CloudFormation Stack
Create your EC2 instance and default security groups:
```bash
aws cloudformation create-stack \
  --stack-name webrtc-to-sip \
  --template-body file://infra/cloudformation/webrtc-to-sip-ec2.yaml \
  --parameters ParameterKey=KeyPairName,ParameterValue=<your-key-pair-name> \
  --capabilities CAPABILITY_IAM
```
*(Wait a few minutes for status to reach `CREATE_COMPLETE`)*

### Step 1.2: Locate EC2 Public IP
Retrieve the public IP address of your newly launched instance:
```bash
aws cloudformation describe-stacks \
  --stack-name webrtc-to-sip \
  --query "Stacks[0].Outputs[?OutputKey=='PublicIP'].OutputValue" \
  --output text
```

---

## Phase 2: Host Initial Setup

### Step 2.1: Connect via SSH
SSH into the instance using the Debian admin username (`admin`):
```bash
ssh -i /path/to/key.pem admin@<EC2_PUBLIC_IP>
```

### Step 2.2: Clone Project Code
Update package indexes, install Git, and clone the repository:
```bash
sudo apt-get update && sudo apt-get install -y git
sudo mkdir -p /opt/webrtc-to-sip
sudo chown admin:admin /opt/webrtc-to-sip
git clone https://github.com/gary391/webrtc-to-sip-ec2.git /opt/webrtc-to-sip/source
cd /opt/webrtc-to-sip/source
```

---

## Phase 3: Setup Configuration & Environment

### Step 3.1: Initialize Environment File
Copy the example template file to `.env`:
```bash
cp .env.example .env
```

### Step 3.2: Detect EC2 Variables
Detect your instance IP addresses, region, and instance ID automatically using the IMDSv2 helper script:
```bash
./deploy/common/detect-ec2-env.sh
```

### Step 3.3: Edit Configuration Credentials
Configure your custom passwords and details:
```bash
nano .env
```
*(Configure `SIP_PASSWORD`, `SIP_PEER_PASSWORD`, `DB_ROOT_PASSWORD`, `DB_KAMAILIO_PASSWORD`, `ADMIN_CIDR`, and `DEMO_CLIENT_CIDR`)*

### Step 3.4: Validate the Environment
Verify that your configurations are valid and there are no network port overlaps:
```bash
./deploy/common/validate-env.sh
```

---

## Phase 4: Run Native Installation

### Step 4.1: Install APT Packages & Build Software
This installs MariaDB, Kamailio, RTPEngine, Nginx, compiles certificates, and sets up static web client paths:
```bash
sudo make native-install
```

### Step 4.2: Render Application Configurations
Process the `.env` settings into dynamic application configuration templates:
```bash
sudo make native-configure
```

---

## Phase 5: Start & Verify Services

### Step 5.1: Start Services
Launch MariaDB, RTPEngine, Kamailio, and Nginx:
```bash
sudo make native-start
```

### Step 5.2: Check Service Statuses
Verify that all systemd services are active and running:
```bash
sudo make native-status
```

### Step 5.3: Run Verification Scripts
Run the status check scripts to ensure that listeners are active and responsive:
```bash
sudo ./deploy/native/verify-status.sh
```

### Step 5.4: Run local test suite
Verify that all settings match the validation constraints of the test suite:
```bash
make test
```

---

## Phase 6: Enable WebSocket Ticket Authentication (Optional)

If you want to gate connections at the Nginx reverse proxy using WebSocket single-use tickets:

### Step 6.1: Update `.env` Configuration
Open your environment file:
```bash
nano .env
```
Ensure the variables are set as follows:
```bash
ENABLE_WS_TICKET_AUTH=true
WS_AUTH_SIDECAR_URL=http://127.0.0.1:9090/validate
WS_TICKET_QUERY_PARAM=ticket
```

### Step 6.2: Apply Configuration Changes
Render Nginx configurations with subrequest ticket validators and restart Nginx:
```bash
sudo make native-configure-nginx
sudo systemctl restart nginx
```

### Step 6.3: Start the Ticket Sidecar Validator
Start the validation server persistently in the background:
```bash
nohup python3 sidecar/ws_ticket_sidecar.py serve --host 127.0.0.1 --port 9090 > /tmp/sidecar.log 2>&1 &
```
Verify that it's running correctly:
```bash
tail -f /tmp/sidecar.log
```

### Step 6.4: Mint a Ticket to Register
Mint a fresh single-use ticket token on the host:
```bash
python3 sidecar/ws_ticket_sidecar.py mint
```
*(Copy the generated `tk_...` token and paste it into the browser client when you click Register)*
