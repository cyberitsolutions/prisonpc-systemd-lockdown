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
chroot /mnt apt install gitit pandoc texlive avahi-daemon-
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
NoNewPrivileges=true
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
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
RestrictRealtime=yes
LockPersonality=yes
RemoveIPC=yes
MemoryDenyWriteExecute=yes
## Not set because we *WANT* /var/log/ntpsec/temps.YYYY-MM-DD.gz to be world-readable.
#Umask=
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
