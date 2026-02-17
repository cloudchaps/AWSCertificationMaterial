#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd

INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
INSTANCE_TYPE=$(ec2-metadata --instance-type | cut -d " " -f 2)
AVAIL_ZONE=$(ec2-metadata --availability-zone | cut -d " " -f 2)
PRIVATE_IP=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)
PUBLIC_IP=$(ec2-metadata --public-ipv4 | cut -d " " -f 2)

# Wait for volume to be attached (check multiple possible device names)
echo "Waiting for attached volume to be available..." > /tmp/mount-debug.log
DEVICE=""
for i in {1..180}; do
  if [ -b /dev/xvdf1 ]; then
    DEVICE="/dev/xvdf1"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  elif [ -b /dev/xvdf ]; then
    DEVICE="/dev/xvdf"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  elif [ -b /dev/sdf1 ]; then
    DEVICE="/dev/sdf1"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  elif [ -b /dev/sdf ]; then
    DEVICE="/dev/sdf"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  elif [ -b /dev/nvme1n1p1 ]; then
    DEVICE="/dev/nvme1n1p1"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  elif [ -b /dev/nvme1n1 ]; then
    DEVICE="/dev/nvme1n1"
    echo "Found device: $DEVICE" >> /tmp/mount-debug.log
    break
  fi
  sleep 1
done

echo "After wait loop - Device: $DEVICE" >> /tmp/mount-debug.log
lsblk >> /tmp/mount-debug.log 2>&1

# Additional wait after device appears
sleep 5

# Mount the snapshot volume
mkdir -p /mnt/snapshot-volume
MOUNT_STATUS="not attempted"
if [ -n "$DEVICE" ] && [ -b "$DEVICE" ]; then
  # Mount with nouuid option for XFS to avoid UUID conflicts
  mount -t xfs -o nouuid,ro "$DEVICE" /mnt/snapshot-volume 2>> /tmp/mount-debug.log
  MOUNT_RESULT=$?
  echo "Mount command result: $MOUNT_RESULT" >> /tmp/mount-debug.log
  if [ $MOUNT_RESULT -eq 0 ]; then
    MOUNT_STATUS="mounted successfully"
  else
    MOUNT_STATUS="mount failed with code $MOUNT_RESULT"
  fi
else
  MOUNT_STATUS="device not found"
fi

echo "Mount status: $MOUNT_STATUS" >> /tmp/mount-debug.log
echo "Contents of /mnt/snapshot-volume:" >> /tmp/mount-debug.log
ls -la /mnt/snapshot-volume >> /tmp/mount-debug.log 2>&1
echo "Mount output:" >> /tmp/mount-debug.log
mount | grep snapshot >> /tmp/mount-debug.log 2>&1

VOLUME_DATA=""
DEBUG_INFO="Device: $DEVICE\nMount Status: $MOUNT_STATUS\n\n"

if [ -f /mnt/snapshot-volume/data/snapshot-data.txt ]; then
  VOLUME_DATA=$(cat /mnt/snapshot-volume/data/snapshot-data.txt)
  echo "Found snapshot-data.txt" >> /tmp/mount-debug.log
else
  echo "snapshot-data.txt not found" >> /tmp/mount-debug.log
  DEBUG_INFO="${DEBUG_INFO}Debug Log:\n$(cat /tmp/mount-debug.log)\n\nDirectory listing:\n$(ls -laR /mnt/snapshot-volume 2>&1)"
fi

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>EC2 Instance Info - Copy</title>
    <style>
        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 50px auto; background: white; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); padding: 40px; }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .info-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #667eea; }
        .label { font-weight: bold; color: #667eea; font-size: 14px; text-transform: uppercase; }
        .value { font-size: 18px; color: #333; margin-top: 5px; word-break: break-all; }
        .snapshot-data { background: #d4edda; padding: 20px; border-radius: 8px; margin-top: 20px; border-left: 4px solid #28a745; }
        .snapshot-data h2 { color: #155724; margin-top: 0; }
        .snapshot-data pre { background: white; padding: 15px; border-radius: 5px; overflow-x: auto; white-space: pre-wrap; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 EC2 Instance (RESTORED from Snapshot)</h1>
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
            <h2>📸 Data from Original Instance Snapshot</h2>
            <pre>$(if [ -n "$VOLUME_DATA" ]; then echo "$VOLUME_DATA"; else echo "$DEBUG_INFO"; fi)</pre>
        </div>
        <div class="footer">AWS CloudChaps Training - Data Restored from EBS Snapshot</div>
    </div>
</body>
</html>
EOF
