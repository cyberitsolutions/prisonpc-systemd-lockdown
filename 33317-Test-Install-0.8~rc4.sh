#!/bin/bash
set -eEu -o pipefail
shopt -s failglob
trap 'echo >&2 "${BASH_SOURCE:-$0}:${LINENO}: unknown error"' ERR

## Reference: https://github.com/zfsonlinux/zfs/wiki/Debian-Buster-Encrypted-Root-on-ZFS

## I assume you're running this inside a live SOE that already has zfs 0.8~rc4 in it.

## These drives are simulating the real prod drives.
HDDs=(
    ata-MB0500EBZQA_Z1M0FBG7    # mirror component
    ata-MB0500EBZQA_Z1M0FGRK    # mirror component
    ata-SAMSUNG_HD501LJ_S0MUJDWQ803564  # cold spare
)
SSDs=(
    usb-TOSHIBA_TOSHIBA_USB_DRV_07087BE3E27D2794-0:0  # ZIL SLOG
    usb-TOSHIBA_TOSHIBA_USB_DRV_07087BE3E51DDF83-0:0  # L2ARC
    usb-Verbatim_STORE_N_GO_070B653669168620-0:0      # EFI ESP disk (on slow USB2 EHCI HBA, not fast USB3 XHCI HBA)
)

## NOTE: NOT USING FULL-DISK ENCRYPTION TODAY

zpool_create_args=(
     -o ashift=12
     -O acltype=posixacl
     -O canmount=off
     -O compression=lz4
     -O dnodesize=auto
     # FIXME: ask #zfsonlinux why this is OK, when Apple found it was
     # a bad idea and removed it in their HFS+ -> APFS transition.
     -O normalization=formD
     -O relatime=on
     -O xattr=sa
     -O mountpoint=/
     -R /mnt                    # FIXME: ???
     # FIXME: what name should we give the pool?
     # UPDATE: one person suggested name it after the host, i.g. "omega" in this case.
     #         I (twb) think I like that, and it matches out convention for LVM VGs.
     omega                       # the name of this pool
     # The nodes.
     mirror "${HDDs[0]}" "${HDDs[1]}"
     spare  "${HDDs[2]}"
     log    "${SSDs[0]}"
     cache  "${SSDs[1]}"
)

zpool create "${zpool_create_args[@]}"

## FIXME: what name should we give the "ROOT" and the zfses?
## NOTE I think the "ROOT" prefix is trying to separate "the" OS from all the "user data" zfses.
## So why aren't all the "user data" zfses created under a common tree like omega/user-data/var/log ?
## This whole thing seems weird and future-proofing for a future that won't happen in my lifetime.

# Everybody gets 1GiB soft limit except for conz, who gets 1.2GiB soft limit.
# UPDATE: fuck it, I'll just let everyone have 2GiB now.

zfs create -o canmount=noauto -o mountpoint=/ -o quota=32G omega/ROOT  # uppercase to distinguish / from /root
zfs mount omega/ROOT

zfs create -o canmount=off                              omega/var
zfs create -o quota=256G                                omega/var/mail  # per-user mail (& list?) mail
zfs create -o quota=8G   -o com.sun:auto-snapshot=false omega/var/tmp  # qemu -snapshot & systemd put stuff here
zfs create -o quota=8G   -o com.sun:auto-snapshot=false omega/var/cache
zfs create -o quota=256G -o com.sun:auto-snapshot=false omega/var/cache/debmirror  # was /srv/apt/debian and /srv/apt/debian-security
zfs create -o quota=32G                                 omega/var/log
zfs create -o quota=8G                                  omega/var/log/journal  # FIXME: does journald actually detect this quota?

zfs create -o canmount=off                              omega/home
zfs create -o quota=2G                                  omega/home/conz
zfs create -o quota=2G                                  omega/home/djk
zfs create -o quota=2G                                  omega/home/jane
zfs create -o quota=2G                                  omega/home/steve
zfs create -o quota=2G                                  omega/home/benf
zfs create -o quota=2G                                  omega/home/neil
zfs create -o quota=2G                                  omega/home/twb
zfs create -o quota=2G                                  omega/home/jeremyc
zfs create -o quota=2G                                  omega/home/russm
zfs create -o quota=2G                                  omega/home/mattcen
zfs create -o quota=2G                                  omega/home/mike
zfs create -o quota=2G                                  omega/home/lachlans
zfs create -o quota=2G                                  omega/home/alla
zfs create -o quota=2G                                  omega/home/dcrisp
zfs create -o quota=2G                                  omega/home/gayle
zfs create -o quota=2G                                  omega/home/chris
zfs create -o quota=2G                                  omega/home/ron
zfs create -o quota=2G                                  omega/home/cjb
zfs create -o quota=2G                                  omega/home/bfoletta

zfs create -o canmount=off                              omega/srv
zfs create -o quota=16G                                 omega/srv/business
zfs create -o quota=16G                                 omega/srv/clients
zfs create -o quota=1G                                  omega/srv/misc  # mostly in-house IRC logs
zfs create -o quota=16G                                 omega/srv/vcs
zfs create -o quota=16G                                 omega/srv/apt  # NOTE: this is "our stuff"; "cache of upstream stuff" will live in var/cache.
zfs create -o quota=2G                                  omega/srv/cctv
zfs create -o quota=4G                                  omega/srv/rrd      # collectd performance monitoring databases
#zfs create                                             omega/srv/kb       # gitit's /var/www ?  Most of that is /srv/vcs/kb/.git...
zfs create -o quota=1G                                  omega/srv/www      # epoxy's /var/www ?  Hardly even worth it...

zfs create -o canmount=off                              omega/ZVOLs
zfs create -V 16G                                       omega/ZVOLs/ESP-DISK  # backup of entire ESP disk, ~16GB, so it's easy to make a new one
zfs create -V 2G                                        omega/ZVOLs/alloc-OS  # /dev/vda (/)
zfs create -V 4G                                        omega/ZVOLs/alloc-DB  # /dev/vdb (/srv/www)
zfs create -V 8G                                        omega/ZVOLs/alloc-FS  # /dev/vdc (/var/lib/mariadb)

# FIXME: not documented enough.  Why aren't we doing chmod 0 on all the mountpoints before creating them?
chmod 1777 /mnt/var/tmp

# FIXME: separate zfs for (samba's equivalent of) /var/lib/ldap?
#        The entire database will be <10MB, so do we EVEN CARE?
# FIXME: separate zfs for /var/backup, which is debian's & our place to drop e.g. sql dumps?
# FIXME: separate zfs for squid forward proxy cache?  Our plan is to not have squid, so don't care.

# FIXME: quickbooks     omega -wi-ao   3.00g --- IS THIS OBSOLETE? --- UPDATE: conz says yes






# This is our rebuild of the zfs 0.8~rc4 packages.
# We use them instead of the buster standard 0.7.13 packages because 0.8 adds support for a systemd mount generator, which makes zfs+systemd work with less hand-holding.
# These packages are currently in Debian NEW queue, and will eventually land in experimental (and then hopefully in unstable, testing, and finally buster-backports).
rsync -ai cyber-buster/ /mnt/srv/apt/cyber-buster/

apt update
apt install debootstrap
## FIXME: for some reason, running debootstrap the first time seems to fail straight away.
## I dunno, maybe DNS is slow to get a SRV record or something.
## Anyway, the second time it works fine, so fuck it, just run it twice.
mkdir /tmp/delete-me
debootstrap buster /tmp/delete-me || :  # usually fails
rm -rf /tmp/delete-me

debootstrap --include=ca-certificates buster /mnt         # FIXME: tweak args
zfs set devices=off omega       # FIXME: this means "mount (most?) datasets with -o nodev"

mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys


>/mnt/etc/hostname echo omega
>/mnt/etc/hosts    cat <<EOF
127.0.0.1  localhost
127.0.1.1  omega.cyber.com.au omega
# FIXME: IPv6 stuff here?
EOF

# FIXME: set up systemd-networkd
rm /mnt/etc/apt/sources.list
>/mnt/etc/apt/sources.list.d/cyber-buster.list echo 'deb file:/srv/apt/cyber-buster/ ./'
>/mnt/etc/apt/sources.list.d/debian.sources cat <<EOF
# Ref. https://manpages.debian.org/stretch/apt/sources.list.5.en.html#DEB822-STYLE_FORMAT
# NOTE: intel-microcode & amd64-microcode needs contrib & non-free!
# FIXME: is it safe to place deb.debian.org and security.debian.org together?
Types: deb
#GOOD#URIs: file:/var/cache/debmirror/debian-security https://deb.debian.org/debian-security http://security.debian.org
URIs: http://apt.cyber.com.au/debian-security  https://deb.debian.org/debian-security http://security.debian.org
Suites: buster/updates
Components: main contrib non-free

# NOTE: "buster-backports" will not work until buster is released (ETA 2019Q2).
Types: deb
#GOOD# URIs: file:/var/cache/debmirror/debian https://deb.debian.org/debian
URIs: http://apt.cyber.com.au/debian  https://deb.debian.org/debian
#GOOD# Suites: buster buster-updates buster-backports
Suites: buster buster-updates
Components: main contrib non-free
EOF


chroot /mnt apt update
chroot /mnt apt install tzdata,locales,linux-image-amd64
chroot /mnt dpkg-reconfigure locales   # set LANG=en_AU.UTF-8
chroot /mnt dpkg-reconfigure tzdata    # set TZ=Australia/Melbourne
>/mnt/etc/apt/apt.conf.d/10stable      echo 'APT::Default-Release "buster";'

# FIXME: install ZFS 0.8~rc4 drivers!!!  (UPDATE: INCLUDING zfs-zed and zfs-dracut and/or zfs-initramfs!)
## Do this using file:/ apt repo, not using HTTP to a host that'll go away as part of this upgrade!!!
## (ACTUALLY, ideally use Debian's own version of this, not our recompile!)
##>/mnt/etc/apt/sources.list.d/zfs0.8.list  echo 'deb [trusted=yes] http://apt.cyber.com.au/internal-buster/ ./'

# FIXME: set up initramfs-tools and kernel pre/postinst hooks to copy /boot/ into /boot/efi/<something>.

# FIXME: try dracut instead of initramfs-tools!!!
chroot /mnt apt install dracut cryptsetup- lvm2- dmraid- mdadm-
## Without -q you can see all the buggy warnings
# root@localhost:~# chroot /mnt dracut --force /boot/initrd.img-4.19.0-4-amd64 4.19.0-4-amd64

chroot /mnt apt install {zfs-dkms,zfsutils-linux,zfs-dracut,spl,spl-dkms,zfs-zed,libnvpair1linux,libuutil1linux,libzfs2linux,libzpool2linux}=0.8.0~rc4-1 build-essential linux-headers-amd64
chroot /mnt apt-mark auto {spl,spl-dkms,zfs-zed,libnvpair1linux,libuutil1linux,libzfs2linux,libzpool2linux} build-essential linux-headers-amd64
chroot /mnt apt install intel-microcode amd64-microcode initramfs-tools-

# FIXME: download refind.img,
#        install it to "/dev/disk/by-id/${SSDs[2]}",
#        fatresize it to 8GB or similar,
#        mount it on /mnt/boot/efi

## FIXME: check checksum and/or .sig?
## UPDATE: resizing is having problems, so probably resort to using the refind INSIDE debian (which has some annoying "helper" code we don't want).
# apt install unzip parted fatresize
# wget --content-disposition https://sourceforge.net/projects/refind/files/0.11.4/refind-flashdrive-0.11.4.zip/download
# unzip refind-flashdrive-0.11.4.zip
# cp refind-flashdrive-0.11.4/refind-flashdrive-0.11.4.img /dev/disk/by-id/"${SSDs[2]}"
# parted /dev/disk/by-id/"${SSDs[2]}" print Fix  # Fix the second GPT (because the .img is smaller than the real disk)
#
# ## FIXME: THIS IS NOT WORKING
# # 18:56 <twb> root@localhost:~# fatresize --info /dev/disk/by-id/"${SSDs[2]}"-part1
# # 18:56 <twb> Error: Could not stat device /dev/disk/by-id/usb-Verbatim_STORE_N_GO_070B653669168620-0:0-part - No such file or directory.
# # 18:56 <twb> stupid hard-coded C crap
# parted /dev/disk/by-id/"${SSDs[2]}" resizepart 1 2GiB
# # 18:59 <twb> After growing the GPT partition, I get this:
# # 18:59 <twb> No Implementation: File system is FAT12, which is unsupported.
# # 18:59 <twb> Which is like... FUCK YOU, gparted handles this JUST FINE
apt update
apt install parted dosfstools
wipefs -a /dev/disk/by-id/"${SSDs[2]}"
parted -saopt /dev/disk/by-id/"${SSDs[2]}" mklabel gpt mkpart ESP-omega 0% 1GiB set 1 esp on
udevadm settle                  # wait for /dev to update
mkfs.vfat -F32 -nESPOMEGA /dev/disk/by-id/"${SSDs[2]}"-part1
install -dm0 /mnt/boot/efi      # NOTE: debootstrap should have already made /mnt/boot
chattr +i /mnt/boot/efi         # If the ESP fails to mount, break, instead of writing into /boot filesystem.
# systemd *sometimes* automounts EFI, and sometimes doesn't.  I have never understood how it decides.
echo LABEL=ESPOMEGA /boot/efi/ vfat defaults 0 0 >>/mnt/etc/fstab

refind-install --usedefault /dev/disk/by-id/"${SSDs[2]}"-part1
mount /dev/disk/by-id/"${SSDs[2]}"-part1 /mnt/boot/efi
# Normally we would ignore /etc/mtab and let systemd-tmpfiles fix it on first boot.
# But refind's postinst script breaks if we don't create it (and have /proc present), so...
#ln -s ../proc/self/mounts /mnt/etc/mtab
#chroot /mnt apt install refind
## UPDATE: that would install to ESP\EFI\REFIND\REFIND_X64.EFI and requires efibootmgr to work.
## If we don't trust efibootmgr to work (or can't access it because we're building and booting on different computers),
## instead of /etc/mtab, we need the ESP to be mountable, but NOT mounted, and then do "refind-install --usedefault ...-part1".

cat >/mnt/boot/refind_linux.conf cat <<EOF
"Boot with standard options"  "root=zfs=omega/ROOT"
EOF
chroot /mnt apt install flash-kernel-efi
chroot /mnt flash-kernel-efi


cp -v /etc/hostid /mnt/etc/hostid


# FIXME: add /tmp tmpfs!  Cap it at (say) 10% of total RAM.

# Set a root password!
chroot /mnt passwd

# FIXME: add hardeninnnnnnnnnnnng!

# FIXME: write a boot/refind_linux.conf (basically just set ROOT=zfs=pool/root)

# The compression algorithm is set to zle because it is the cheapest
# available algorithm. As this guide recommends ashift=12 (4 kiB
# blocks on disk), the common case of a 4 kiB page size means that no
# compression algorithm can reduce I/O. The exception is all-zero
# pages, which are dropped by ZFS; but SOME form of compression has to
# be enabled to get this behavior.  Hence, zle.
zfs create -V 4G -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false omega/ZVOLs/SWAP
mkswap -f /dev/zvol/omega/ZVOLs/SWAP
## ADD SWAP TO FSTAB?  WHAT ABOUT THE WHOLE "AUTO DISCOVER MOUNTPOINTS" STUFF THAT SYSTEMD WAS PROMOTING FOR SINGLE-OS COMPUTERS?  SPECIAL UUIDS OR SOMETHING?
# The RESUME=none is necessary to disable resuming from hibernation. This does not work, as the zvol is not present (because the pool has not yet been imported) at the time the resume script
# runs. If it is not disabled, the boot process hangs for 30 seconds waiting for the swap zvol to appear.
echo RESUME=none >/mnt/etc/initramfs-tools/conf.d/resume
#swapon /dev/zvol/omega/swap     # to test it


######################################################################
### We need to activate zfs-mount-generator. This makes systemd aware of the separate mountpoints, which is important for things like /var/log and /var/tmp. In turn, rsyslog.service depends on

mkdir /mnt/etc/zfs/zfs-list.cache
touch /mnt/etc/zfs/zfs-list.cache/omega
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /mnt/etc/zfs/zed.d  # ????
chroot /mnt zed -F &
# Verify that zed updated the cache by making sure this is not empty:
cat /mnt/etc/zfs/zfs-list.cache/omega
# If it is empty, force a cache update and check again:
zfs set canmount=noauto omega/ROOT
pkill zed
# Fix the paths to eliminate /mnt:  [TWB: UGGGGGGH]
sed -ri "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/omega


# Snapshot the initial installation:
zfs snapshot -r omega@install-1


# FIXME: Do some I/O performance testing w/ and w/o the slog and friends.
# Using bio(8), or what?

## FIXME: this should all happen via SAMBA'S ADMIN TOOLS
## 6.6 Create a user account:
# zfs create rpool/home/YOURUSERNAME
# adduser YOURUSERNAME
# cp -a /etc/skel/.[!.]* /home/YOURUSERNAME
# chown -R YOURUSERNAME:YOURUSERNAME /home/YOURUSERNAME
## 6.7 Add your user account to the default set of groups for an administrator:
# usermod -a -G audio,cdrom,dip,floppy,netdev,plugdev,sudo,video YOURUSERNAME


## FIXME: disable gzip compression of /var/log/* in /etc/logrotate,
## because ZFS is already doing LZ4 compression, so fuck it?
## Actually, do ZSTD compression for omega/var/log zfs?


## DURING TESTING, USE TINYSSHD.
## DURING PROD, USE OPENSSH-SERVER BECAUSE BETTER RATE-LIMITING.

chroot /mnt apt install openssh-server curl wget wget2
chroot /mnt install -dm700 /root/.ssh
chroot /mnt wget -O- http://cyber.com.au/~twb/.ssh/authorized_keys >/mnt/root/.ssh/authorized_keys

chroot /mnt systemctl enable systemd-network
cat >/mnt/etc/systemd/network/upstream.network <<EOF
[Match]
Name=enp11s0
[Network]
DHCP=yes
DNSSEC=no
[DHCP]
UseDomain=yes
EOF


chroot /mnt apt install etckeeper
chroot /mnt apt install aptitude
chroot /mnt apt install nocache
chroot /mnt apt install apparmor apparmor-profiles apparmor-utils libpam-apparmor apparmor-easyprof apparmor-profiles-extra  # libapache2-mod-apparmor
chroot /mnt apt install ntpsec ntpsec-ntpdate  # FIXME: THIS IS FOR NEW ALPHA, **NOT** NEW OMEGA
##chroot /mnt apt install ntpsec-ntpviz gnuplot-nox gnuplot-qt-   # apache2-
chroot /mnt apt install samba winbind smbclient libpam-krb5 krb5-user ldb-tools
chroot /mnt apt install gitit pandoc texlive avahi-daemon- nodejs-
chroot /mnt apt install strace curl w3m wget wget2 squashfs-tools hdparm
chroot /mnt apt install emacs-nox emacs-el elpa-debian-el elpa-devscripts elpa-systemd
chroot /mnt apt install build-essential devscripts dpkg-dev pkgconf at-
chroot /mnt apt install bash-completion
chroot /mnt apt install postfix postfix-lmdb dovecot-imapd dovecot-lucene dovecot-sieve dovecot-managesieved dovecot-lmtpd procmail-
chroot /mnt apt install systemd-cron cron-
chroot /mnt apt install libnss-systemd libnss-myhostname libnss-resolve
chroot /mnt apt install systemd-coredump
chroot /mnt apt install knot-dnsutils
chroot /mnt apt install gitolite3
chroot /mnt apt install gnupg2 tig
chroot /mnt apt install nginx-light apache2-
chroot /mnt apt install fail2ban
chroot /mnt apt install nsd
chroot /mnt apt install charybdis atheme limnoria     # OR charybdis->ircd-hybrid (no SASL?); OR atheme-services->anope

#chroot /mnt apt install qemu-user-binfmt qemu-user-static  # let me run an ARM64 chroot on X86_64 hardware.


# work around a bug that was confusing aa-genprof?
chroot /mnt touch /etc/apparmor.d/local/{usr.sbin.dovecot,usr.lib.dovecot.{deliver,managesieve,managesieve-login,imap,imap-login,dovecot-lda,auth,pop3-login,config,dict,pop3,log,anvil,ssl-params,dovecot-auth,lmtp}}


## debspawn needs /dev/null to work in in /var/tmp/debspawn
## root@not-omega:~/mg# zfs create -o devices=on omega/var/tmp/debspawn
## root@not-omega:~/mg# debspawn create testing
## root@not-omega:~/mg# debspawn create testing --mirror=http://apt.cyber.com.au/debian


# Making alamo using an openvz/LXC-style container, rather than a full VM.
zfs create -o canmount=off                              omega/var/lib
zfs create -o canmount=off                              omega/var/lib/machines
zfs create -o quota=4G                                  omega/var/lib/machines/alamo
chroot /mnt systemctl enable systemd-nspawn@alamo


cat >/mnt/etc/systemd/system/charybdis.service <<'EOF'
[Unit]
Description=Charybdis IRC server
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
User=charybdis
ExecStartPre=/usr/bin/charybdis -conftest
ExecStart=/usr/bin/charybdis
ExecReload=/bin/kill -HUP $MAINPID

ProtectSystem=full
RuntimeDirectory=charybdis
NoNewPrivileges=yes
CapabilityBoundingSet=~CAP_SYS_ADMIN
CapabilityBoundingSet=~CAP_DAC_OVERRIDE
CapabilityBoundingSet=~CAP_SYS_CHROOT

[Install]
WantedBy=multi-user.target
EOF

## This script is total shit, and it's only actually used when statistics are enabled in ntp.conf.
## We should probably just "systemctl disable" its corresponding .timer unit.
## And if we *do* turn on stats, expiring old ones sounds like a job for /etc/logrotate.d/!
mkdir /mnt/etc/systemd/system/ntpsec-rotate-stats.service.d
cat >/mnt/etc/systemd/system/ntpsec-rotate-stats.service.d/override.conf <<'EOF'
# FIXME: convince upstream to use logrotate instead of an equivalent sh script!
[Service]
PrivateNetwork=yes
User=ntpsec
PrivateUsers=yes
PrivateNetwork=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
PrivateDevices=yes
PrivateTmp=yes
ProtectHome=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
ReadWritePaths=-/var/log/ntpsec/
WorkingDirectory=/var/log/ntpsec
IPAddressDeny=any
SystemCallArchitectures=native
RestrictNamespaces=yes
NoNewPrivileges=yes

# This is the conservative baseline suggested by "systemd-analyze security".
# It breaks because gzip tries to call fchown(2).
#SystemCallFilter=@system-service
#SystemCallFilter=~@privileged @resources
# This doesn't work because the aliases "overlap"
#SystemCallFilter=@system-service @chown
#SystemCallFilter=~@privileged @resources
# Doing it as "add lots, then remove some, then re-add a little" works.
# If that made no sense, try wdiffing before/after of "systemctl show",
# to see the exact list of syscalls that end up in the allow list.
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallFilter=@chown

RestrictRealtime=yes
LockPersonality=yes
RemoveIPC=yes
MemoryDenyWriteExecute=yes
# FIXME: ntpsec logs are world-readable.  Should we restrict them to e.g. adm group?
UMask=0022

# Resource exhaustion (i.e. DOS) isn't covered by "systemd-analyze security", but
# WE care about it.  This is the lowest priority available.
# See also logrotate.service.
# MemoryHigh= mitigates read-once jobs flushing fscache (see https://github.com/Feh/nocache)
# TasksMax= mitigates accidental forkbombs.
# CPUQuota=100% limits the slice to equivalent of 100% of a single CPU core
# CPUWeight=
[Service]
Nice=19
CPUSchedulingPolicy=batch
IOSchedulingClass=idle
MemoryHigh=128M
TasksMax=16
CPUQuota=50%
EOF


mkdir /mnt/etc/systemd/system.conf.d
cat >/mnt/etc/systemd/system.conf.d/override.conf <<'EOF'
# Enable accounting for all things.  (Imposes a performance overhead, but probably negligible.)
[Manager]
DefaultCPUAccounting=yes
DefaultIOAccounting=yes
DefaultIPAccounting=yes
DefaultBlockIOAccounting=yes
DefaultMemoryAccounting=yes
DefaultTasksAccounting=yes
EOF


mkdir /mnt/etc/systemd/system/apt-cacher-ng.service.d
cat >/mnt/etc/systemd/system/apt-cacher-ng.service.d/override.conf <<'EOF'
[Service]
# apt-cacher-ng needs network access
PrivateNetwork=no
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
#IPAddressDeny=any
#IPAddressAllow=localhost

User=apt-cacher-ng
PrivateUsers=yes
RuntimeDirectory=apt-cacher-ng
WorkingDirectory=/run/apt-cacher-ng

CapabilityBoundingSet=
PrivateDevices=yes
PrivateTmp=yes
ProtectHome=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
ReadWritePaths=-/var/cache/apt-cacher-ng /var/log/apt-cacher-ng
SystemCallArchitectures=native
RestrictNamespaces=yes
NoNewPrivileges=yes
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
RemoveIPC=yes
MemoryDenyWriteExecute=yes
## By default /var/cache/apt-cacher-ng/ is world-readable, but
## AFAICT it's not *needed*, so appease "systemd-analyze security".
UMask=0077
EOF


mkdir /mnt/etc/systemd/system/rsync.service.d
cat >/mnt/etc/systemd/system/rsync.service.d/override.conf <<'EOF'
[Service]
# rsyncd needs network access
PrivateNetwork=no
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
#IPAddressDeny=any
#IPAddressAllow=localhost

# We don't use User= here, because
#  * the rsync package doesn't create one by default;
#  * rsyncd needs CAP_NET_BIND to bind to the default port (873);
#  * rsyncd needs CAP_SYS_CHROOT if you "use chroot"; and
#  * rsyncd.conf can have >1 share, with *DIFFERENT* chroots and users.
#User=my-rsync-user
# We don't use PrivateUsers= here, because
#  * rsyncd.conf doesn't use "numeric ids" by default.
#PrivateUsers=yes
# These don't really help, but they don't hurt either.
RuntimeDirectory=rsync
WorkingDirectory=/run/rsync

# If you're just exporting something like /srv/rsync or /var/cache/foo,
# all of these can be protected.
PrivateDevices=yes
PrivateTmp=yes
ProtectHome=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
# This is how you'd add just the exported areas, implicitly making everything else read-only.
# NOTE: ReadOnlyPaths= is a lot harder to use, because
# you'd need to whitelist things like /etc/rsyncd.conf and /lib/blah.
#ReadWritePaths=-/srv/rsync /var/log/rsync
# Adopt a hardline (EVERYTHING is read-only) by default, because
#  * in rsyncd.conf, "read only" is on by default;
#  * in rsyncd.conf, logging is via stdio by default (not /var/log nor /dev/log); and
#  * (AFAIK) rsyncd is mostly "anonymous read-only" access, like FTP.
ReadWritePaths=

CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SYS_CHROOT CAP_SETUID CAP_SETGID
SystemCallArchitectures=native
RestrictNamespaces=yes
NoNewPrivileges=yes
SystemCallFilter=@system-service chroot
# SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
# WARNING: RemoveIPC= only works if you use User=!
RemoveIPC=yes
MemoryDenyWriteExecute=yes
# I *think* this has no effect because rsyncd tends to chmod by default anyway.
# It probably changes the permissions of logfiles if you use "log file" instead of stdout/syslog.
UMask=0077
EOF



## Just create users in /etc/ for now, because Samba AD DS is too fucking hard.
## NOTE: we lose the Description field for groups!
##
## These users & groups were copy-pasted from LDAP on 2019-05-20.

chroot /mnt adduser --disabled-password --no-create-home --uid=1024 --gecos='Con Zymaris' conz
chroot /mnt adduser --disabled-password --no-create-home --uid=1025 --gecos='David Keegel' djk
chroot /mnt adduser --disabled-password --no-create-home --uid=1026 --gecos='Jane Zymaris' jane
chroot /mnt adduser --disabled-login    --no-create-home --uid=1027 --gecos="Steven D'Aprano" steve
chroot /mnt adduser --disabled-login    --no-create-home --uid=1028 --gecos='Ben Finney' benf
chroot /mnt adduser --disabled-password --no-create-home --uid=1029 --gecos='Ron Fabre' ron
chroot /mnt adduser --disabled-password --no-create-home --uid=1030 --gecos='Neil Murray' neil
chroot /mnt adduser --disabled-password --no-create-home --uid=1031 --gecos='Trent W. Buck' twb
chroot /mnt adduser --disabled-login    --no-create-home --uid=1032 --gecos='Jeremy Chin' jeremyc
chroot /mnt adduser --disabled-password --no-create-home --uid=1033 --gecos='Russell Muetzelfeldt' russm
chroot /mnt adduser --disabled-login    --no-create-home --uid=1034 --gecos='Brendan Foletta' bfoletta
chroot /mnt adduser --disabled-password --no-create-home --uid=1035 --gecos='Christopher Bayliss' cjb
chroot /mnt adduser --disabled-login    --no-create-home --uid=1036 --gecos='Matthew Cengia' mattcen
chroot /mnt adduser --disabled-password --no-create-home --uid=1037 --gecos='Michael Abrahall' mike
chroot /mnt adduser --disabled-login    --no-create-home --uid=1038 --gecos='Lachlan Simpson' lachlans
chroot /mnt adduser --disabled-login    --no-create-home --uid=1039 --gecos='Alex Lance' alla
chroot /mnt adduser --disabled-login    --no-create-home --uid=1040 --gecos='David Crisp' dcrisp
chroot /mnt adduser --disabled-password --no-create-home --uid=1042 --gecos='Gayle Fabre' gayle
chroot /mnt adduser --disabled-login    --no-create-home --uid=1043 --gecos='Christian Julius' chris

chroot /mnt chown -h 1024 /home/conz
chroot /mnt chown -h 1025 /home/djk
chroot /mnt chown -h 1026 /home/jane
chroot /mnt chown -h 1027 /home/steve
chroot /mnt chown -h 1028 /home/benf
chroot /mnt chown -h 1029 /home/ron
chroot /mnt chown -h 1030 /home/neil
chroot /mnt chown -h 1031 /home/twb
chroot /mnt chown -h 1032 /home/jeremyc
chroot /mnt chown -h 1033 /home/russm
chroot /mnt chown -h 1034 /home/bfoletta
chroot /mnt chown -h 1035 /home/cjb
chroot /mnt chown -h 1036 /home/mattcen
chroot /mnt chown -h 1037 /home/mike
chroot /mnt chown -h 1038 /home/lachlans
chroot /mnt chown -h 1039 /home/alla
chroot /mnt chown -h 1040 /home/dcrisp
chroot /mnt chown -h 1042 /home/gayle
chroot /mnt chown -h 1043 /home/chris

chroot /mnt addgroup --gid=2048 cyber
chroot /mnt addgroup --gid=2049 responsible
chroot /mnt addgroup --gid=2050 managers
chroot /mnt addgroup --gid=2051 allocadm
chroot /mnt addgroup --gid=2052 jobs
chroot /mnt addgroup --gid=2053 office
chroot /mnt addgroup --gid=2054 accounts
chroot /mnt addgroup --gid=2055 clips
chroot /mnt addgroup --gid=2056 datasafer_dev
chroot /mnt addgroup --gid=2057 info
chroot /mnt addgroup --gid=2058 sales
chroot /mnt addgroup --gid=2059 support
chroot /mnt addgroup --gid=2060 prisonpc_dev
chroot /mnt addgroup --gid=2061 tech
chroot /mnt addgroup --gid=2062 sbls_dev
chroot /mnt addgroup --gid=2063 trivia
chroot /mnt addgroup --gid=2064 oldlists
chroot /mnt addgroup --gid=2065 securitycamera
chroot /mnt addgroup --gid=2066 sftponly
chroot /mnt addgroup --gid=2067 salessupport
chroot /mnt addgroup --gid=2068 sysadmin
chroot /mnt addgroup --gid=2069 payroll
chroot /mnt addgroup --gid=2070 hccep

# GENERATED BY: ssh login getent group {2049..4096} | sort -t: -k3 | cut -d: -f1,4 | while IFS=: read -r k v; do tr , '\n' <<<"$v" | while read -r v2; do echo chroot /mnt adduser "$v2" "$k"; done; done
chroot /mnt adduser twb responsible
chroot /mnt adduser russm responsible
chroot /mnt adduser mike responsible
chroot /mnt adduser conz managers
chroot /mnt adduser djk managers
chroot /mnt adduser jane managers
chroot /mnt adduser ron managers
chroot /mnt adduser alla allocadm
chroot /mnt adduser djk allocadm
chroot /mnt adduser conz jobs
chroot /mnt adduser ron jobs
chroot /mnt adduser conz office
chroot /mnt adduser djk office
chroot /mnt adduser gayle office
chroot /mnt adduser jane office
chroot /mnt adduser neil office
chroot /mnt adduser russm office
chroot /mnt adduser twb office
chroot /mnt adduser ron office
chroot /mnt adduser mike office
chroot /mnt adduser jane accounts
chroot /mnt adduser conz clips
chroot /mnt adduser djk clips
chroot /mnt adduser gayle clips
chroot /mnt adduser neil clips
chroot /mnt adduser russm clips
chroot /mnt adduser ron clips
chroot /mnt adduser mike clips
chroot /mnt adduser russm datasafer_dev
chroot /mnt adduser ron datasafer_dev
chroot /mnt adduser conz info
chroot /mnt adduser ron info
chroot /mnt adduser conz sales
chroot /mnt adduser ron sales
chroot /mnt adduser conz support
chroot /mnt adduser twb prisonpc_dev
chroot /mnt adduser mattcen prisonpc_dev
chroot /mnt adduser ron prisonpc_dev
chroot /mnt adduser russm prisonpc_dev
chroot /mnt adduser djk prisonpc_dev
chroot /mnt adduser mike prisonpc_dev
chroot /mnt adduser conz tech
chroot /mnt adduser djk tech
chroot /mnt adduser mattcen tech
chroot /mnt adduser neil tech
chroot /mnt adduser russm tech
chroot /mnt adduser twb tech
chroot /mnt adduser ron tech
chroot /mnt adduser mike tech
chroot /mnt adduser ron sbls_dev
chroot /mnt adduser mike sbls_dev
chroot /mnt adduser conz trivia
chroot /mnt adduser djk trivia
chroot /mnt adduser gayle trivia
chroot /mnt adduser jane trivia
chroot /mnt adduser mattcen trivia
chroot /mnt adduser neil trivia
chroot /mnt adduser russm trivia
chroot /mnt adduser ron trivia
chroot /mnt adduser mike trivia
chroot /mnt adduser conz oldlists
chroot /mnt adduser djk oldlists
chroot /mnt adduser jane oldlists
chroot /mnt adduser neil oldlists
chroot /mnt adduser ron oldlists
chroot /mnt adduser mike oldlists
chroot /mnt adduser conz securitycamera
chroot /mnt adduser djk securitycamera
chroot /mnt adduser ron securitycamera
chroot /mnt adduser dcrisp sftponly
chroot /mnt adduser benf sftponly
chroot /mnt adduser lachlans sftponly
chroot /mnt adduser chris sftponly
chroot /mnt adduser bfoletta sftponly
chroot /mnt adduser gayle salessupport
chroot /mnt adduser ron salessupport
chroot /mnt adduser twb sysadmin
chroot /mnt adduser ron sysadmin
chroot /mnt adduser mike sysadmin
chroot /mnt adduser jane payroll
chroot /mnt adduser ron hccep
chroot /mnt adduser conz hccep
chroot /mnt adduser djk hccep


# The old LDAP group "responsible" is very similar to standard group "adm".
# Being a member of "adm" lets you read the system journal without sudo.
# Add members here.
chroot /mnt adduser twb adm
chroot /mnt adduser russm adm
chroot /mnt adduser mike adm


#BROKEN# mkdir /mnt/etc/systemd/system/dovecot.service.d
#BROKEN# cat >/mnt/etc/systemd/system/dovecot.service.d/override.conf <<'EOF'
#BROKEN# ## See also upstream history:
#BROKEN# ##  https://github.com/dovecot/core/commits/master/dovecot.service.in
#BROKEN# 
#BROKEN# [Service]
#BROKEN# # apt-cacher-ng needs network access
#BROKEN# PrivateNetwork=no
#BROKEN# RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
#BROKEN# #IPAddressDeny=any
#BROKEN# #IPAddressAllow=localhost
#BROKEN# 
#BROKEN# # It's not feasible to put systemd in charge of user management here, because
#BROKEN# #   * like postfix, dovecot runs its own management daemon, and a bunch of helper daemons "under" it.
#BROKEN# #   * it also needs to switch EUID when a user logs in, so e.g. imaps://alice@127.1/ runs *as* alice.
#BROKEN# #User=apt-cacher-ng
#BROKEN# #PrivateUsers=yes
#BROKEN# # These don't really help, but they don't hurt either.
#BROKEN# RuntimeDirectory=dovecot
#BROKEN# WorkingDirectory=/run/dovecot
#BROKEN# 
#BROKEN# # NOTE: upstream says they tried NoNewPrivileges and it didn't work!
#BROKEN# #       https://github.com/dovecot/core/commit/a66e595515ab579a875a2e9b8116be5da45fb5d6#diff-5bbec0a0006d92d441b5c8fa72690f95
#BROKEN# NoNewPrivileges=no
#BROKEN# CapabilityBoundingSet=
#BROKEN# PrivateDevices=yes
#BROKEN# # NOTE: upstream already sets PrivateTmp=yes
#BROKEN# PrivateTmp=yes
#BROKEN# # 20:05 <twb> I guess PrivateHome=no is needed for sieve and stuff, even if the actual mailboxes live in /var ???
#BROKEN# ProtectHome=no
#BROKEN# ProtectControlGroups=yes
#BROKEN# ProtectKernelModules=yes
#BROKEN# ProtectKernelTunables=yes
#BROKEN# ProtectSystem=strict
#BROKEN# ReadWritePaths=-/var/cache/apt-cacher-ng /var/log/apt-cacher-ng
#BROKEN# SystemCallArchitectures=native
#BROKEN# RestrictNamespaces=yes
#BROKEN# SystemCallFilter=@system-service
#BROKEN# SystemCallFilter=~@privileged @resources
#BROKEN# RestrictRealtime=yes
#BROKEN# LockPersonality=yes
#BROKEN# RemoveIPC=yes
#BROKEN# MemoryDenyWriteExecute=yes
#BROKEN# ## By default /var/cache/apt-cacher-ng/ is world-readable, but
#BROKEN# ## AFAICT it's not *needed*, so appease "systemd-analyze security".
#BROKEN# UMask=0077
#BROKEN# EOF


mkdir /mnt/etc/systemd/system/fstrim.service.d
cat >/mnt/etc/systemd/system/fstrim.service.d/override.conf <<'EOF'
# fstrim's "active ingredient" is ioctl(openat('/mountpoint'), FITRIM).
#
# That is, it
#   * MUST be able to see the mounts (ProtectHome &c)
#   * MUST have CAP_SYS_ADMIN to issue the FITRIM (CapabilityBoundingSet)
#   * MAY have -oro mounts (ReadWritePaths)
#   * MAY have raw disk access blocked (PrivateDevices)
#
# UPDATE: fstrim.c:has_discard() needs sysfs access.
#         AFAICT, that still works OK even with PrivateDevices=yes and Protect*=yes,
#         but maybe I just got lucky.


[Service]
PrivateNetwork=yes
RestrictAddressFamilies=AF_UNIX
IPAddressDeny=any
PrivateDevices=yes

RuntimeDirectory=fstrim
WorkingDirectory=/run/fstrim

# With ProtectHome=yes, fstrim -Av silently ignores trimmable mounts at/under /home!
ProtectHome=no
# With ProtectTmp=yes, fstrim -Av silently ignores trimmable mounts at/under /tmp!
# Enabled anyway, because /tmp is usually either 1) a tmpfs or 2) part of /.
PrivateTmp=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes

# CAP_SYS_ADMIN is needed to issue FITRIM ioctls.
CapabilityBoundingSet=CAP_SYS_ADMIN
# With User=nobody or PrivateUsers=yes, the ioctl fails.
#User=nobody
#PrivateUsers=yes

ProtectSystem=strict
ReadWritePaths=

SystemCallArchitectures=native
RestrictNamespaces=yes
NoNewPrivileges=yes
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
RemoveIPC=yes
MemoryDenyWriteExecute=yes
UMask=0077
EOF

mkdir /mnt/etc/systemd/system/apt-daily.service.d
cat >/mnt/etc/systemd/system/apt-daily.service.d/override.conf <<'EOF'
## WARNING: this assumes apt >= 1.4.1-4-g496313fb8
##                    or apt >= 1.3.6-4-ga234cfe14.
## Newer versions run postinsts in apt-daily-upgrade.service.
## Older versions run postinsts in *this* unit, and will be upset by lockdown.

[Service]
# These things all seem to Just Work.
DevicePolicy=closed
LockPersonality=yes
MemoryDenyWriteExecute=yes
NoNewPrivileges=yes
PrivateDevices=yes
PrivateMounts=yes
PrivateTmp=yes
ProtectControlGroups=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallArchitectures=native

# No PrivateNetwork=yes because HTTP mirrors are very common.
# If your /etc/apt/sources.list.d only uses file: or cdrom:, you might lock this down further.
# UPDATE: "apt-helper wait-online" runs "systemd-networkd-wait-online", which needs AF_NETLINK (to systemd-networkd).
PrivateNetwork=no
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
#IPAddressDeny=any

## We can't drop privileges here (User=_apt), because /var/lib/apt/lists is root:root.
## Rely on apt to drop privileges correctly on its own.
User=root
RemoveIPC=no
PrivateUsers=no
CapabilityBoundingSet=CAP_SETUID CAP_SETGID

# If non-default APT::Periodic::Download-Upgradeable-Packages is used,
# "unattended-upgrades -d" runs, and it needs
#  * write access to /var/log/unattended-upgrades/
#  * write access to /run/unattended-upgrades.lock
#  * write access to /run/unattended-upgrades.pid
#
# I don't *think* we actually use /var/log/apt or /var/log/dpkg.log, but
# I'm granting write access to all of /var/log/ anyway, as "good enough".
ProtectSystem=strict
ReadWritePaths=-/var/lib/apt /var/cache/apt /var/log /run /var/backups

# With the "systemd-analyze security" recommended settings, apt-get coredumps.
#SystemCallFilter=@system-service
#SystemCallFilter=~@privileged @resources
SystemCallFilter=@system-service

# This removes group- and world-read access to:
#   /var/lib/apt/periodic/*
#   /var/lib/apt/lists/partial/*
# It does NOT affect these:
#   /var/lib/apt/lists/deb.debian.org_*
UMask=0077

# DOS-related security.
# Declare that this is a batch job with slightly lower priority than the default.
[Service]
Nice=5
CPUSchedulingPolicy=batch
IOSchedulingClass=best-effort
EOF


for unit in cron-{hourly,daily,weekly,monthly}
do
    mkdir -p /mnt/etc/systemd/system/"$unit".service.d
    cat  >/mnt/etc/systemd/system/"$unit".service.d/low-priority.conf <<-'EOF'
	# Assume that timer-fired jobs (systemd-cron, logrotate, man-db)
	# are low-priority batch jobs.
	# Upstream already downgrades logrotate and man-db to LOWEST priority.
	# We downgrade the others about halfway.
	#
	# Nice=0 is default; Nice=19 is nicest.
	# IOSchedulingPriority=4 is the default, range is 0 through 7 inclusive.
	[Service]
	Nice=15
	CPUSchedulingPolicy=batch
	IOSchedulingClass=best-effort
	IOSchedulingPriority=6
	EOF
done

for unit in etckeeper systemd-tmpfiles-clean
do
    mkdir -p /mnt/etc/systemd/system/etckeeper.service.d
    cat  >/mnt/etc/systemd/system/etckeeper.service.d/low-priority.conf <<-'EOF'
	# Upstream sets idle but not nice or batch.
	[Service]
	Nice=19
	CPUSchedulingPolicy=batch
	#IOSchedulingClass=idle
	EOF
done



mkdir /mnt/etc/systemd/system/logrotate.service.d
cat >/mnt/etc/systemd/system/logrotate.service.d/override.conf <<-'EOF'
# Debian's logrotate.service does some reasonable lockdown by default.
#
# Logrotate MUST be able to do variations on "pkill -HUP frobozzd",
# to make frobozzd reopen its rotated logfile.
# That means it probably needs e.g. AF_NETLINK for "systemctl kill -USR1".
#
# In principle the scripts could do arbitrary things (e.g. ejecting a tape), but
# I think we can reasonably block those things by default and let weird users loosen them again.
[Service]
# Logrotate must be able to su/chown to arbitrary users.
User=root
PrivateUsers=no
CapabilityBoundingSet=CAP_SETUID CAP_SETGID CAP_CHOWN
RestrictNamespaces=yes

# mariadb needs this because /var/log/mysql is mysql:adm 2750.
# If root is an ordinary user (no DAC_OVERRIDE), she can't edit that.
# Most logs are root:foo 77x or foo:root 77x, which works without this.
CapabilityBoundingSet=CAP_DAC_OVERRIDE

# The "no brainer" lockdown options.
LockPersonality=yes
NoNewPrivileges=yes
ProtectKernelTunables=yes
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@resources
UMask=0077

# FIXME: is this needed?  I *think* I needed it to rotate mysql/error.log.
SystemCallFilter=@chown

# Upstream Debian doesn't PrivateHome= because of "userdir logging".
# IMO if you log to /home/alice/virtualenv/frobozzd-1/log
# instead of /var/log/frobozzd, you are bad and you SHOULD feel bad.
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/var/log /var/lib/logrotate/

# Upstream says MemoryDenyWriteExecute breaks gzip built with ASM686.
# gzip w/ASM686 is not DFSG-compliant, so Debian is safe!
MemoryDenyWriteExecute=yes

# Upstream won't do this because you might do "mail me@example.com" to a logrotate.conf.
# We do that via logcheck, so it's entirely reasonable to block lock this down.
# NOTE: msmtp-mta needs PrivateNetwork=no.
# NOTE: postfix maildrop needs AF_NETLINK.
PrivateNetwork=yes
RestrictAddressFamilies=AF_UNIX
IPAddressDeny=any

# Resource exhaustion (i.e. DOS) isn't covered by "systemd-analyze security", but
# WE care about it
# MemoryHigh= mitigates read-once jobs flushing fscache (see https://github.com/Feh/nocache)
# TasksMax= mitigates accidental forkbombs.
# CPUQuota=100% limits the slice to equivalent of 100% of a single CPU core
# CPUWeight=
# NOTE: upstream already sets Nice= and IOSchedulingClass=
CPUSchedulingPolicy=batch
TasksMax=16
MemoryHigh=128M
CPUQuota=50%
EOF


mkdir /mnt/etc/systemd/system/cron.service.d
cat >/mnt/etc/systemd/system/cron.service.d/override.conf <<-'EOF'
# Cron needs to run fairly arbitrary things, so there is little we can do to lock it down.
# For example, it needs write access to /var and /home.
# It needs to be able to use /usr/sbin/sendmail
# Since I intend to use systemd-cron (not ISC Vixie cron),
# I'm not even bothering to do cursory experimentation with this. --twb, May 2019
EOF


mkdir /mnt/etc/systemd/system/systemd-hwdb-update.service.d
cat >/mnt/etc/systemd/system/systemd-hwdb-update.service.d/override.conf <<-'EOF'
# This ultimately just calls src/libsystemd/sd-hwdb/hwdb-util.c:hwdb_update()
# It merges text files /???/udev/hwdb.d/*.hwdb into a single binary /etc/udev/hwdb.bin.
# Therefore, we can lock it down like billy-o, yay!
[Service]

# This is, like, the MOST OBVIOUS THING.
ReadWritePaths=/etc/udev/

# /etc/udev/hwdb.bin is root-owned.
User=root

# PrivateUsers=yes didn't work:
#   Failed to set up user namespacing: Resource temporarily unavailable
PrivateUsers=no

PrivateNetwork=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
DevicePolicy=closed
RestrictNamespaces=yes
IPAddressDeny=any
NoNewPrivileges=yes
PrivateDevices=yes
PrivateMounts=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
UMask=0077

# Resource exhaustion (i.e. DOS) isn't covered by "systemd-analyze security", but
# WE care about it.
# NOTE: NOT setting IOSchedulingClass=idle, because this is part of early boot!
TasksMax=1
CPUSchedulingPolicy=batch
CPUQuota=100%
EOF


mkdir /mnt/etc/systemd/system/systemd-udev-settle.service.d
cat >/mnt/etc/systemd/system/systemd-udev-settle.service.d/override.conf <<-'EOF'
# This unit is deprecated, because it doesn't do what people think it does.
# People think it means "wait until all devices have appeared".
# It actually means "wait until in-progress devices are fully processed".
# As at Debian 10 / ZOL 0.8.0, ZFS is pulling this in, so we might as well lock it down.
[Service]
PrivateNetwork=yes
DynamicUser=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
DevicePolicy=closed
IPAddressDeny=any
NoNewPrivileges=yes
PrivateDevices=yes
# PrivateUsers=yes didn't work:
#   Failed to set up user namespacing: Resource temporarily unavailable
PrivateUsers=no
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
UMask=0077
ReadWritePaths=
# Resource exhaustion (i.e. DOS) isn't covered by "systemd-analyze security", but
# WE care about it.
# NOTE: NOT setting IOSchedulingClass=idle, because this is part of early boot!
TasksMax=1
CPUSchedulingPolicy=batch
MemoryHigh=64M
CPUQuota=25%
EOF


mkdir /mnt/etc/systemd/system/systemd-udev-trigger.service.d
cat >/mnt/etc/systemd/system/systemd-udev-trigger.service.d/override.conf <<-'EOF'
# I *THINK* this unit just writes things into /sys/, but that might be optimistic...
# I'm frankly too scared to try locking this one down yet. ---twb, May 2019
EOF


mkdir /mnt/etc/systemd/system/systemd-udevd.service.d
cat >/mnt/etc/systemd/system/systemd-udevd.service.d/override.conf <<-'EOF'
# I'm frankly too scared to try locking this one down yet. ---twb, May 2019
EOF

## SKIPPING IFUPDOWN BECAUSE I ONLY USE SYSTEMD-NETWORKD (FOR NOW).
# 81	ifupdown	/lib/systemd/system/ifup@.service
# 81	ifupdown	/lib/systemd/system/ifupdown-pre.service
# 81	ifupdown	/lib/systemd/system/ifupdown-wait-online.service
# 81	ifupdown	/lib/systemd/system/networking.service

mkdir /mnt/etc/systemd/system/rsyslog.service.d
cat >/mnt/etc/systemd/system/rsyslog.service.d/override.conf <<-'EOF'
# rsyslog can read and write log events from several places.
# The main cases *I* care about are:
#  1. Debian default - read from journald (& klog) and write to /var/log;
#  2. Best-practice satellite log client - as #1, and write to RELP; &
#  3. Best-practice central log server - as #1, and read from RELP (and legacy syslog).
#
# PS: Debian default enables omusrmsg, too, for e.g. "logger -p 0 IDIOT ON TTY1".
#
# I will cover #1 first, then have #2/#3 as an amendment.
# Things like writing to a PostgreSQL database are not covered here.

# Notes:
#  • imuxsock needs AF_UNIX.
#  • imklog needs CAP_SYS_ADMIN to read /proc/kmsg (i.e. dmesg).
#  • omfile needs PrivateUsers=no to resolve "adm" group &c.
[Service]
PrivateNetwork=yes
User=root
RestrictAddressFamilies=AF_UNIX
CapabilityBoundingSet=CAP_SYS_ADMIN
RestrictNamespaces=yes
DevicePolicy=closed
IPAddressDeny=any
NoNewPrivileges=yes
PrivateDevices=yes
PrivateTmp=yes
PrivateUsers=no
ProtectControlGroups=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallArchitectures=native
LockPersonality=yes
MemoryDenyWriteExecute=yes
UMask=0077

# Blocking @resources caused rsyslogd to hang during startup.
# I haven't investigated why.
SystemCallFilter=@system-service @resources
SystemCallFilter=~@privileged

ProtectSystem=strict
ReadWritePaths=/var/log
# Because postfix is chrooted, it puts a dropin into /etc/rsyslog.d/
# asking imuxsock to listen inside the chroot (in addition to the
# normal /dev/log or /run/systemd/journal/syslog).  All the other
# rsyslog.d/ files in Debian 10 just make extra /var/log files.
ReadWritePaths=-/var/spool/postfix

##############################
### Uncomment this block if you logging over the network.
##############################
# • imtcp/imudp need CAP_NET_BIND_SERVICE to use port 514.
# • imtcp/imudp/imrelp/omrelp need AF_INET and AF_INET6.
PrivateNetwork=no
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressDeny=
EOF


mkdir /mnt/etc/systemd/system/man-db.service.d
cat >/mnt/etc/systemd/system/man-db.service.d/override.conf <<-'EOF'
# NOTE: Upstream already locks down User= Nice= IOSchedulingClass=.
[Service]
PrivateNetwork=yes
CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
DevicePolicy=closed
IPAddressDeny=any
NoNewPrivileges=yes
PrivateDevices=yes
PrivateTmp=yes
PrivateUsers=yes
ProtectControlGroups=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RemoveIPC=yes
UMask=0077
ProtectSystem=strict
ReadWritePaths=-/var/cache/man

# Resource exhaustion (i.e. DOS) isn't covered by "systemd-analyze security".
# I watched this run on a basic Debian 10 server,
# it peaked at 16MB memory and 4 tasks.
MemoryHigh=64M
CPUSchedulingPolicy=batch
TasksMax=16
CPUQuota=25%
EOF


mkdir /mnt/etc/systemd/system/dbus.service.d
cat >/mnt/etc/systemd/system/dbus.service.d/override.conf <<-'EOF'
# I'm frankly too scared to try locking this one down yet. ---twb, May 2019

# /join #systemd
# 19:47 <twb> Does dbus.service need AF_INET6 access?
# 19:47 <twb> Isn't it purely AF_UNIX?
# 19:49 <grawity> normally it should be purely AF_UNIX
# 19:50 <grawity> it's configurable to listen on TCP sockets, but if your system bus is bound to TCP, you have big problems
# 19:50 <twb> I was gonna add some "systemd-analyze security" mojo to it, but since it's needed for things like "systemctl daemon-reload", I decided it was too scary
# 19:50 <grawity> well, if you break it, systemctl can just fall back to the private socket
# 19:51 <grawity> however... dbus-daemon *does* directly fork auto-activated bus services, if they do not have a corresponding systemd .service yet
# 19:51 <grawity> and *those* might need AF_INET6 etc
# 19:51 <twb> Interesting
# 19:51 <grawity> though again, shouldn't be many of those left on the system bus
# 19:52 <grawity> with most services either having systemd-based activation instead, or being non-activatable
# 19:52 <grawity> busctl --system --activatable
# 19:53 <grawity> I don't think I've recently had anything but dbus-daemon in my dbus.service cgroup, so that's fine
# 19:53 <grawity> session/user bus is a different story, still most DE stuff activated directly
EOF




mkdir /mnt/etc/systemd/system/ssh.service.d
cat >/mnt/etc/systemd/system/ssh.service.d/override.conf <<-'EOF'
# /join #systemd
# 19:56 <twb> If I lock down ssh.service, that doesn't affect users ssh'ing in, right?  Because they end up in a user slice, as confirmed in "systemctl status"
# 19:57 <grawity> well, the user process still starts in ssh.service
# 19:57 <grawity> it is moved to a different cgroup later, but that doesn't necessarily allow it to shake off all restrictions, e.g. seccomp
# 19:57 <grawity> only those that are actually cgroup-bound
# 19:58 <twb> does "cgroup-bound" also include ns stuff?  e.g. PrivateHome
# 19:59 <grawity> no
# 19:59 <twb> Owie
# 20:00 <grawity> that's process-specific, a privileged process can e.g. umount systemd's "privacy" overlay or outright switch back to the initial namespace via /proc, but that isn't automatic at all
# 20:01 <twb> Well, at a high level I'm asking what things from "systemd-analyze security ssh" I can put into ssh.service.d/twb.conf, without breaking user sessions that are started via ssh'ing in
# 20:01 <grawity> probably very little
# 20:02 <grawity> sshd already has decent privilege separation built in, though, so I'd say keep it as is
# 20:02 <grawity> if anything, trying to contain it too much would just break the privsep feature
# 20:03 <twb> The purpose of lockdown in the systemd unit isn't to replace lockdown in the daemon, it's defense-in-depth against bugs in the daemon
# 20:04 <twb> OpenSSH itself is pretty good, but it can still be pwned by badness in third-party PAM or NSS modules
# 20:05 <grawity> 1) don't use those, 2) PAM in particular kinda has to be privileged for many modules to do their job, doesn't it
# 20:06 <twb> OpenSSH itself advises people just to leave UsePAM off entirely.  Of course, systemd-logind doesn't like that.
# 20:07 <grawity> mostly because it's an OpenBSD thing and OpenBSD doesn't even have PAM
EOF

mkdir /mnt/etc/systemd/system/ssh@.service.d
cat >/mnt/etc/systemd/system/ssh@.service.d/override.conf <<-'EOF'
# The comments in ssh.service.d/override.conf apply here as well.
EOF

# 20:09 <twb> I assume getty@ and getty-serial@ go into the same bucket as ssh?
# 20:10 <grawity> yes
# 20:10 <twb> Righto


mkdir /mnt/etc/systemd/system/nginx.service.d
cat >/mnt/etc/systemd/system/nginx.service.d/override.conf <<-'EOF'
# In Debian 10 Buster, systemd 241 provides "systemd-analyze security".
# This tells you all the things you can do to constrain a service unit.
#
# The idea of this file is a combination of "default-deny" and
# "defence-in-depth" doctrines.  If something should NEVER HAPPEN,
# then it doesn't hurt to encoding that in the daemon *and* in
# systemd, *and* in AppArmor/SELinux!  That way, if one layer screws
# up, it will still be blocked.
#
# FOR EXAMPLE, dovecot.service should never need to modprobe netconsole.ko;
# if it tries that, something is DEEPLY wrong, and it can be blocked.
#
#
# While *I* think systemd lockdown should be "opt out", systemd only provides an "opt in" mechanism.
# That means every time systemd adds a new security feature, overworked daemon maintainers need to know about it and try turning it on.
# Otherwise, it does nothing.
#
# As a sysadmin, adding in opt-ins by hand gets a bit repetetive.
# The purpose of THIS FILE is to provide a reference to simplify that process.
# There are two parts:
#
#   1. DEFAULT DENY   (this is the same for all units)
#   2. ALLOW          (this is unit-specific and includes a rationale)
#
# Note that if a unit says Foo=bar Foo=baz, they (usually) "add together".
# To "zero out" a rule, you instead need Foo=bar Foo= Foo=baz, to get ONLY baz.
#
# WARNING: "systemd-analyze security" DOES NOT list ALL .service units.
# e.g. it lists rsync.service even if you have no /etc/rsyncd.conf.
# e.g. it omits logrotate.service even though a timer runs it.
#
# WARNING: DO NOT try to lock down getty or ssh.  Even though
# pam_systemd.so + logind cause the user session to be reparented into
# its own slice, grawity on #systemd says that lockdown of getty/ssh
# WILL still affect the user session.
#
# WARNING: be extra careful of anything with DefaultDependencies=no.
# These are usually early boot units, and
# some things like PrivateUsers= seem to Just Not Work for them?
#
# References:
#   https://manpages.debian.org/systemd.exec
#   https://manpages.debian.org/systemd.resource-control


######################################################################
# DEFAULT DENY
######################################################################
# The order of these rules is the order they appear in
# "systemd-analyze security foo", which is descending importance.
[Service]
PrivateNetwork=yes
#DynamicUser=
User=frobozzd
CapabilityBoundingSet=
# RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
DevicePolicy=closed
IPAddressDeny=any
#KeyringMode=private
NoNewPrivileges=yes
PrivateDevices=yes
PrivateMounts=yes
PrivateTmp=yes
PrivateUsers=yes
ProtectControlGroups=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
SystemCallArchitectures=native
#AmbientCapabilities=
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
#RootDirectory/RootImage=
#SupplementaryGroups=
#Delegate=
LockPersonality=yes
MemoryDenyWriteExecute=yes
UMask=0077

# systemd-analyze security doesn't mention this, but it's relevant!
# You might be tempted to downgrade ProtectSystem=strict to ProtectSystem=full.
# If you only need a couple of writable dirs, you can whitelist them specifically.
#ReadWritePaths=
#ReadWritePaths=/var/lib/frobozz
#ReadWritePaths=-/var/log/frobozz /var/cache/frobozz

# systemd-analyze security does not consider service denial attacks.  We do!
# Some need tuning for the host's hardware/load/role.
# Therefore I am leaving them as "opt in" for now.
# These three are equivalent to "nice ionice -c3 chrt --idle 0".
# It puts it at the back of the queue when it comes to resource allocation.
# These are appropriate for "cron job" type processes, but NOT daemons.
#Nice=10
#CPUSchedulingPolicy=batch
#IOSchedulingClass=idle
# This says it can use up to one CPU core's worth of time.
# It's appropriate for things SHOULD be single threaded.
# It's not appropriate for things like pigz or xz -T0.
# This is likely to be a hardware-specific choice.
#CPUQuota=100%
# This mitigates forkbombs.
# Even something like apache can probably set a high mark here.
#TasksMax=16
# SHORT VERSION: use MemoryHigh= (instead of nocache) for jobs like updatedb.
# LONG VERSION follows.
# RAM is faster than HDD, so Linux uses idle RAM as an HDD cache, the "page cache".
# When apps need more RAM, part of the page cache must be thrown away.
# The "page replacement algorithm" decides which page is least useful.
# As at 2019, the default PRA ("LRU") is old and stupid.
# https://linux-mm.org/PageReplacementDesign
# As at 2019, an alternative is not ready.
# https://linux-mm.org/AdvancedPageReplacement
#
# In the meantime, a workload that reads a lot of disk blocks ONCE
# will trick the LRU into flushing the page cache, ruining read I/O for other processes.
# Examples include: updatedb, du, find.
#
# When your unit acts like one of these, you can wrap it in nocache,
# which uses LD_PRELOAD to add FADV_DONTNEED to most disk I/O.
# https://github.com/Feh/nocache
#
# A more robust alternative is to set MemoryHigh= to more than the
# process needs, but much less than the amount of RAM you have.
# Because MemoryHigh= count includes page cache,
# it should prevent the unit from flushing the WHOLE page cache.
# https://www.kernel.org/doc/Documentation/cgroup-v2.txt
# It is hard to know in advance what a good number for this should be.
# This is likely to be a unit-specific choice.
# Some units will scale with load, e.g. dovecot, postfix, apache.
# Some units won't scale with load, e.g. man-db.
#MemoryHigh=128M


######################################################################
# OPT-IN ALLOW (WITH RATIONALE)
######################################################################


# nginx must listen on a low port then drop privs itself, because
# it is NOT socket activated (cf. CUPS for a counterexample).
# FIXME: why is AF_NETLINK needed?
User=
PrivateUsers=no
PrivateNetwork=no
RestrictAddressFamilies=AF_INET AF_INET6
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID
SystemCallFilter=@setuid
IPAddressDeny=
# nginx must have write access to logs, because
# it does NOT use syslog or stdio.
ReadWritePaths=/var/log/nginx
# nginx wants write access to /run/nginx.pid.
ReadWritePaths=/run
# FIXME: instead change /run/nginx.pid to /run/nginx/nginx.pid!
#X#RuntimeDirectory=nginx
#X#PIDFile=/run/nginx/nginx.pid
# nginx needs CAP_DAC_OVERRIDE because logrotate makes nginx's logs www-data:adm 640, but
# nginx opens them as root *before* dropping privileges.
CapabilityBoundingSet=CAP_DAC_OVERRIDE

# This mitigates forkbombs.
# Set a "high water mark" well above what we expect to reach, but
# well below what a forkbomb could otherwise achieve.
# Ref. http://nginx.org/en/docs/ngx_core_module.html#thread_pool
#      http://nginx.org/en/docs/ngx_core_module.html#worker_processes
TasksMax=1000
# HOST SPECIFIC: I have 8 CPU cores; nginx can have up to 4 cores.
CPUQuota=400%
# HOST SPECIFIC: I have 16GB of RAM; penalize nginx when it goes over 4GB.
MemoryHigh=4G
EOF



mkdir /mnt/etc/systemd/system/smartd.service.d
cat >/mnt/etc/systemd/system/smartd.service.d/override.conf <<-'EOF'
# In Debian 10 Buster, systemd 241 provides "systemd-analyze security".
# This tells you all the things you can do to constrain a service unit.
#
# USAGE:
#   1. systemctl edit frobozz.service
#   2. paste in this file, edit ALLOW rules, save, quit
#   3. systemctl restart frobozz || systemctl status frobozz
#   4. if it failed, go to 1
#
# The idea of this file is a combination of "default-deny" and
# "defence-in-depth" doctrines.  If something should NEVER HAPPEN,
# then it doesn't hurt to encoding that in the daemon *and* in
# systemd, *and* in AppArmor/SELinux!  That way, if one layer screws
# up, it will still be blocked.
#
# FOR EXAMPLE, dovecot.service should never need to modprobe netconsole.ko;
# if it tries that, something is DEEPLY wrong, and it can be blocked.
#
#
# While *I* think systemd lockdown should be "opt out", systemd only provides an "opt in" mechanism.
# That means every time systemd adds a new security feature, overworked daemon maintainers need to know about it and try turning it on.
# Otherwise, it does nothing.
#
# As a sysadmin, adding in opt-ins by hand gets a bit repetetive.
# The purpose of THIS FILE is to provide a reference to simplify that process.
# There are two parts:
#
#   1. DEFAULT DENY   (this is the same for all units)
#   2. ALLOW          (this is unit-specific and includes a rationale)
#
# Note that if a unit says Foo=bar Foo=baz, they (usually) "add together".
# To "zero out" a rule, you instead need Foo=bar Foo= Foo=baz, to get ONLY baz.
#
# WARNING: "systemd-analyze security" DOES NOT list ALL .service units.
# e.g. it lists rsync.service even if you have no /etc/rsyncd.conf.
# e.g. it omits logrotate.service even though a timer runs it.
#
# WARNING: DO NOT try to lock down getty or ssh.  Even though
# pam_systemd.so + logind cause the user session to be reparented into
# its own slice, grawity on #systemd says that lockdown of getty/ssh
# WILL still affect the user session.
#
# WARNING: be extra careful of anything with DefaultDependencies=no.
# These are usually early boot units, and
# some things like PrivateUsers= seem to Just Not Work for them?
#
# References:
#   https://manpages.debian.org/systemd.exec
#   https://manpages.debian.org/systemd.resource-control


######################################################################
# DEFAULT DENY
######################################################################
# The order of these rules is the order they appear in
# "systemd-analyze security foo", which is descending importance.
[Service]
PrivateNetwork=yes
#DynamicUser=
User=frobozzd
# CapabilityBoundingSet=
RestrictAddressFamilies=AF_UNIX
RestrictNamespaces=yes
DevicePolicy=closed
IPAddressDeny=any
#KeyringMode=private
NoNewPrivileges=yes
PrivateDevices=yes
PrivateMounts=yes
PrivateTmp=yes
PrivateUsers=yes
ProtectControlGroups=yes
ProtectHome=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
ProtectSystem=strict
SystemCallArchitectures=native
#AmbientCapabilities=
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
#RootDirectory/RootImage=
#SupplementaryGroups=
#Delegate=
LockPersonality=yes
MemoryDenyWriteExecute=yes
UMask=0077

# systemd-analyze security doesn't mention this, but it's relevant!
# You might be tempted to downgrade ProtectSystem=strict to ProtectSystem=full.
# If you only need a couple of writable dirs, you can whitelist them specifically.
#ReadWritePaths=
#ReadWritePaths=/var/lib/frobozz
#ReadWritePaths=-/var/log/frobozz /var/cache/frobozz

# When a daemon wants to make /run/frobozz.pid,
# you might be tempted to ProtectSystem=full or ReadWritePaths=/run.
# It is tighter to RuntimeDirectory=frobozz and tell the daemon to use
# /run/frobozz/frobozz.pid.

# systemd-analyze security does not consider service denial attacks.  We do!
# Some need tuning for the host's hardware/load/role.
# Therefore I am leaving them as "opt in" for now.
# These three are equivalent to "nice ionice -c3 chrt --idle 0".
# It puts it at the back of the queue when it comes to resource allocation.
# These are appropriate for "cron job" type processes, but NOT daemons.
#Nice=10
#CPUSchedulingPolicy=batch
#IOSchedulingClass=idle
# This says it can use up to one CPU core's worth of time.
# It's appropriate for things SHOULD be single threaded.
# It's not appropriate for things like pigz or xz -T0.
# This is likely to be a hardware-specific choice.
#CPUQuota=100%
# This mitigates forkbombs.
# Even something like apache can probably set a high mark here.
#TasksMax=16
# SHORT VERSION: use MemoryHigh= (instead of nocache) for jobs like updatedb.
# LONG VERSION follows.
# RAM is faster than HDD, so Linux uses idle RAM as an HDD cache, the "page cache".
# When apps need more RAM, part of the page cache must be thrown away.
# The "page replacement algorithm" decides which page is least useful.
# As at 2019, the default PRA ("LRU") is old and stupid.
# https://linux-mm.org/PageReplacementDesign
# As at 2019, an alternative is not ready.
# https://linux-mm.org/AdvancedPageReplacement
#
# In the meantime, a workload that reads a lot of disk blocks ONCE
# will trick the LRU into flushing the page cache, ruining read I/O for other processes.
# Examples include: updatedb, du, find.
#
# When your unit acts like one of these, you can wrap it in nocache,
# which uses LD_PRELOAD to add FADV_DONTNEED to most disk I/O.
# https://github.com/Feh/nocache
#
# A more robust alternative is to set MemoryHigh= to more than the
# process needs, but much less than the amount of RAM you have.
# Because MemoryHigh= count includes page cache,
# it should prevent the unit from flushing the WHOLE page cache.
# https://www.kernel.org/doc/Documentation/cgroup-v2.txt
# It is hard to know in advance what a good number for this should be.
# This is likely to be a unit-specific choice.
# Some units will scale with load, e.g. dovecot, postfix, apache.
# Some units won't scale with load, e.g. man-db.
#MemoryHigh=128M


######################################################################
# OPT-IN ALLOW (WITH RATIONALE)
######################################################################

# WARNING: smartd.conf -M exec can do ARBITRARY THINGS.
#          You may need to whitelist additional things.
# smartd must run as root to have direct disk access?
# FIXME: would User=smartd Group=disk be sufficient?
User=
# smartd must be able to issue ioctls directly to disks.
# FIXME: "block-sd" suffices for SATA and USB HDDs.
#        What about other device types?
#        (NOTE: /dev/nvme0 is char-nvme, and /dev/nvme0n1 is block-blkext)
# FIXME: allowing block-blkext on a host without NVMe results in a warning from _PID=1!
# FIXME: if both Allows are on the same line, and
#        the above warning happens, the
#        entire line is ignored (instead of just block-blkext)!
#        Is that a systemd bug?  Ask upstream!
PrivateDevices=no
DeviceAllow=block-sd
DeviceAllow=block-blkext
# UPDATE: @raw-io isn't needed for AHCI (SATA), at least.
#X#SystemCallFilter=@raw-io
# FIXME: why does smartd need the ability to resolve other users?
#        Is it dropping privileges to "nobody" for some actions?
#        With PrivateUsers=yes, all devices (wrongly) report:
#            Device: /dev/sda, IE (SMART) not enabled, skip device
#            Try 'smartctl -s on /dev/sda' to turn on SMART features
#            Unable to monitor any SMART enabled devices. Try debug (-d) option. Exiting...
PrivateUsers=no

# smartd on Debian will by default email you about problems (-m root).
# smartd calls /usr/bin/mail, which calls /usr/sbin/sendmail.
# This will fail unless we allow things the /usr/sbin/sendmail needs.
# (NOTE: /usr/sbin/sendmail is a generic interface; it's not "the" sendmail!)
# postfix maildrop needs AF_NETLINK
# postfix maildrop needs write access to the spool
# postfix maildrop needs the setgid bit on /usr/bin/postdrop to work! (PrivateUsers=no)
# postfix maildrop complains if INET/INET6 are blocked, even though
#                  they're only used by other parts of postfix.
RestrictAddressFamilies=AF_NETLINK AF_INET AF_INET6
ReadWritePaths=/var/spool/postfix/maildrop
PrivateUsers=no
# msmtp-mta needs network access to the submission (587/tcp) server.
#PrivateNetwork=no
#RestrictAddressFamilies=AF_INET AF_INET6
#IPAddressDeny=
EOF
