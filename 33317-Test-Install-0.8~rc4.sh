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
zfs set devices=off omega       # ????

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
