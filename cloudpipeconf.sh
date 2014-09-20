#!/bin/bash

###########################################
#
# Turn base ubuntu image into cloudpipe
#
###########################################


PACKAGES="vim openvpn vzctl bridge-utils unzip"

function eprint {
    echo "updating $FILE ..."
}


# first of all, install openvpn and vzctl

apt-get update

apt-get -y install $PACKAGES

if [ $? = "0" ]; then
    echo "successful packages installation!"
else
    echo "error during packages installation!"
    exit 1
fi



#edit /etc/rc.local

FILE="/etc/rc.local"
eprint

cat > $FILE << FILE_EOF

. /lib/lsb/init-functions
 
LOG=/tmp/rc.log
SUCCESS=false
COUNT=0
ADDR=\$(ip addr show br0 | egrep -o "inet [0-9\.]+" | cut -d' ' -f2)
echo "Booting..." > \$LOG
while [ \$COUNT -lt 10 ]; do
  echo "[count: \$COUNT]: Trying to download payload from userdata..." >> \$LOG
  wget --header="X-Forwarded-For: \$ADDR" http://169.254.169.254/latest/user-data -O /tmp/payload.b64 && SUCCESS=true
  [ \$SUCCESS = true ] && break
  COUNT=\`expr \$COUNT + 1\`
  sleep 5
done
 
echo "Sending Gratuitous ARP..." >> \$LOG
arpsend -U -i \$ADDR br0 -c 1
 
if [ \$SUCCESS = true ]; then
  echo "Decrypting base64 payload" >> \$LOG
  openssl enc -d -base64 -in /tmp/payload.b64 -out /tmp/payload.zip
 
  mkdir -p /tmp/payload
  echo Unzipping payload file >> \$LOG
  unzip -o /tmp/payload.zip -d /tmp/payload/
fi
if [ -e /tmp/payload/autorun.sh ]; then
  echo Running autorun.sh >> \$LOG
  cd /tmp/payload
  sh /tmp/payload/autorun.sh
else
  echo rc.local : No autorun script to run >> \$LOG
fi
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i tun0 -d 192.168.0.0/32 -j DROP
iptables -A INPUT -i tun0 -j DROP 
iptables -A INPUT -p TCP --dport 22 -i eth0 -j ACCEPT
iptables -A INPUT -p UDP --dport 1194 -i eth0 -j ACCEPT
iptables -A INPUT -i eth0 -j DROP
 
exit 0
FILE_EOF


#edit /etc/openvpn/server.conf.template

FILE="/etc/openvpn/server.conf.template"
eprint
cat > $FILE << FILE_EOF
port 1194
proto udp
dev tun
 
persist-key
persist-tun

ca ca.crt
cert server.crt
key server.key
 
dh dh1024.pem
 
 
client-to-client
keepalive 10 120
comp-lzo
 
max-clients 1
 
user nobody
group nogroup
 
status openvpn-status.log
status openvpn.log
 
verb 3
mute 20

mssfix 1360
fragment 1360
tun-mtu 1400
 
management 0.0.0.0 7505
FILE_EOF


exit 0
