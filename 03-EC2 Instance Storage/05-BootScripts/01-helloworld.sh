#!/bin/bash
# Use this to install httpd (Linux 2 version - Amazon linux 2 AMI Preferred)
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd

# Get EC2 instance metadata
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
INSTANCE_TYPE=$(ec2-metadata --instance-type | cut -d " " -f 2)
AVAIL_ZONE=$(ec2-metadata --availability-zone | cut -d " " -f 2)
PRIVATE_IP=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)
PUBLIC_IP=$(ec2-metadata --public-ipv4 | cut -d " " -f 2)
CREATION_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Create data directory and sample data file
mkdir -p /data
cat > /data/snapshot-data.txt <<DATA
=== Original Instance Data ===
Instance ID: $INSTANCE_ID
Availability Zone: $AVAIL_ZONE
Creation Time: $CREATION_TIME
Private IP: $PRIVATE_IP

This data was created on the original instance and should be visible
on all instances created from the snapshot across different AZs.
DATA

# Check if additional volume is mounted
VOLUME_DATA=""
if [ -b /dev/xvdf ]; then
  # Mount the additional volume if it exists
  mkdir -p /mnt/snapshot-volume
  mount /dev/xvdf /mnt/snapshot-volume 2>/dev/null
  if [ -f /mnt/snapshot-volume/snapshot-data.txt ]; then
    VOLUME_DATA=$(cat /mnt/snapshot-volume/snapshot-data.txt)
  fi
fi

# Create HTML page with EC2 info and snapshot data
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>EC2 Instance Info</title>
    <style>
        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 50px auto; background: white; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); padding: 40px; }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .info-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #667eea; }
        .label { font-weight: bold; color: #667eea; font-size: 14px; text-transform: uppercase; }
        .value { font-size: 18px; color: #333; margin-top: 5px; word-break: break-all; }
        .snapshot-data { background: #fff3cd; padding: 20px; border-radius: 8px; margin-top: 20px; border-left: 4px solid #ffc107; }
        .snapshot-data h2 { color: #856404; margin-top: 0; }
        .snapshot-data pre { background: white; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 EC2 Instance Information</h1>
        <div class="info-grid">
            <div class="info-card">
                <div class="label">Instance ID</div>
                <div class="value">$INSTANCE_ID</div>
            </div>
            <div class="info-card">
                <div class="label">Instance Type</div>
                <div class="value">$INSTANCE_TYPE</div>
            </div>
            <div class="info-card">
                <div class="label">Availability Zone</div>
                <div class="value">$AVAIL_ZONE</div>
            </div>
            <div class="info-card">
                <div class="label">Private IP</div>
                <div class="value">$PRIVATE_IP</div>
            </div>
            <div class="info-card">
                <div class="label">Public IP</div>
                <div class="value">$PUBLIC_IP</div>
            </div>
            <div class="info-card">
                <div class="label">Hostname</div>
                <div class="value">$(hostname -f)</div>
            </div>
        </div>
        <div class="snapshot-data">
            <h2>📸 Snapshot Volume Data</h2>
            <pre>$(if [ -n "$VOLUME_DATA" ]; then echo "$VOLUME_DATA"; else echo "No snapshot volume mounted at /dev/xvdf\n\nThis is the ORIGINAL instance. Data from /data/snapshot-data.txt:\n\n$(cat /data/snapshot-data.txt)"; fi)</pre>
        </div>
        <div class="footer">AWS CloudChaps Training Instance - Snapshot Demo</div>
    </div>
</body>
</html>
EOF