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

# Create HTML page with EC2 info
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
        <div class="footer">AWS CloudChaps Training Instance</div>
    </div>
</body>
</html>
EOF