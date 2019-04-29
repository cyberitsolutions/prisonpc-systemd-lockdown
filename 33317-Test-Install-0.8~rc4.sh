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
    usb-Verbatim_STORE_N_GO_070B653669168620-0:0      # EFI ESP drive (on slow USB2 EHCI HBA, not fast USB3 XHCI HBA)
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

zfs create -o canmount=noauto -o mountpoint=/ omega/OS/root
zfs mount omega/OS/root
zfs create -o com.sun:auto-snapshot=false     omega/OS/var/cache
zfs create -o com.sun:auto-snapshot=false     omega/OS/var/cache/apt/debian
zfs create -o com.sun:auto-snapshot=false     omega/OS/var/cache/apt/debian-security
zfs create -o com.sun:auto-snapshot=false     omega/OS/var/tmp
users=(conz djk jane steve benf neil twb jeremyc russm mattcen mike lachlans alla dcrisp gayle chris ron cjb bfoletta)
for user in "${users[@]}"
do
    zfs create -o mountpoint=/home/"$user"     -o quota=2G  omega/USER/"$user"/home
    zfs create -o mountpoint=/var/mail/"$user"              omega/USER/"$user"/mail
done

zfs create -o mountpoint=/var/mail/Lists   omega/USER/ALL/mail
zfs create -o mountpoint=/var/log          omega/DATA/log
zfs create -o mountpoint=/var/log/journal  omega/DATA/journal
zfs create                                 omega/var/spool # WHY MAKE THIS AT ALL?
chmod 1777 /mnt/var/tmp         # FIXME: not documented enough.  Why aren't we doing chmod 0 on all the mountpoints before creating them?
zfs create                                 omega/srv/business  # User documents (FIXME: use a common root?)
zfs create                                 omega/srv/clients   # User documents (FIXME: use a common root?)
zfs create                                 omega/srv/misc      # User documents (FIXME: use a common root?)
zfs create                                 omega/srv/vcs
zfs create                                 omega/srv/apt    # NOTE: this is "our stuff"; "cache of upstream stuff" will live in var/cache.
zfs create                                 omega/srv/cctv
zfs create                                 omega/srv/rrd      # collectd performance monitoring databases
zfs create                                 omega/srv/kb       # gitit's /var/www ?  Most of that is /srv/vcs/kb/.git...
zfs create                                 omega/srv/www      # epoxy's /var/www ?  Hardly even worth it...

# FIXME: create "sensible" quotas on most of these volums
# FIXME: create per-user zfses for /home, and set each to a 1GB quota, to encourage people to store things in git or the KB?
# FIXME: create per-user zfses for /var/mail/conz?

# create a zvol for a backup of the entire ESP disk, ~16GB, so it's easy to make a new one.
zfs create -V 16G                           omega/OS/ESP-DISK

# FIXME: create a zvol for alloc VM's OS      /dev/vda (/)
# FIXME: create a zvol for alloc VM's allocfs /dev/vdb (/srv/www)
# FIXME: create a zvol for alloc VM's allocdb /dev/vdc (/var/lib/mariadb)
zfs create -V 2G                            omega/OS/alloc-OS
zfs create -V 4G                            omega/alloc-DB
zfs create -V 8G                            omega/alloc-FS

# FIXME: IRC logs go where?  ---> /srv/misc
# FIXME: separate zfs for (samba's equivalent of) /var/lib/ldap?
#        The entire database will be <10MB, so do we EVEN CARE?
# FIXME: separate zfs for /var/backup, which is debian's & our place to drop e.g. sql dumps?
# FIXME: separate zfs for squid forward proxy cache?  Our plan is to not have squid, so don't care.

# FIXME: quickbooks     omega -wi-ao   3.00g --- IS THIS OBSOLETE?


# FIXME: download refind.img,
#        install it to "/dev/disk/by-id/${SSDs[2]}",
#        fatresize it to 8GB or similar,
#        mount it on /mnt/boot/efi

debootstrap --include=tzdata,locales buster /mnt         # FIXME: tweak args
zfs set devices=off omega       # ????

cd /mnt
>etc/hostname echo omega
>etc/hosts    cat <<EOF
127.0.0.1  localhost
127.0.1.1  omega.cyber.com.au omega
# FIXME: IPv6 stuff here?
EOF

# FIXME: set up systemd-networkd
rm etc/apt/sources.list
>/etc/apt/sources.list.d/debian.sources <<EOF
# Ref. https://manpages.debian.org/stretch/apt/sources.list.5.en.html#DEB822-STYLE_FORMAT
# NOTE: intel-microcode & amd64-microcode needs contrib & non-free!
# FIXME: is it safe to place deb.debian.org and security.debian.org together?
Types: deb
URIs: file:/var/cache/apt/debian-security https://deb.debian.org/debian-security http://security.debian.org
Suites: buster/updates
Components: main contrib non-free

# NOTE: "buster-backports" will not work until buster is released (ETA 2019Q2).
Types: deb
URIs: file:/var/cache/apt/debian https://deb.debian.org/debian
Suites: buster buster-updates buster-backports
Components: main contrib non-free
EOF

chroot . apt update

# mount --rbind /dev  /mnt/dev
# mount --rbind /proc /mnt/proc
# mount --rbind /sys  /mnt/sys
# chroot /mnt /bin/bash --login

chroot . dpkg-reconfigure locales   # set LANG=en_AU.UTF-8
chroot . dpkg-reconfigure tzdata    # set TZ=Australia/Melbourne
>etc/apt/apt.conf.d/10stable         echo "APT::Default-Release \"$r\";"

# FIXME: install ZFS 0.8~rc4 drivers!!!
## Do this using file:/ apt repo, not using HTTP to a host that'll go away as part of this upgrade!!!
## (ACTUALLY, ideally use Debian's own version of this, not our recompile!)
##>$t/etc/apt/sources.list.d/zfs0.8.list  echo 'deb [trusted=yes] http://apt.cyber.com.au/internal-buster/ ./'

# FIXME: set up initramfs-tools and kernel pre/postinst hooks to copy /boot/ into /boot/efi/<something>.

# FIXME: try dracut instead of initramfs-tools!!!

# FIXME: add /tmp tmpfs!  Cap it at (say) 10% of total RAM.

# Set a root password!
chroot . passwd

# FIXME: add hardeninnnnnnnnnnnng!

# FIXME: write a boot/refind_linux.conf (basically just set ROOT=zfs=pool/root)

# FIXME: swap zvol?
## FIXME: getconf???
# The compression algorithm is set to zle because it is the cheapest available algorithm. As this guide recommends ashift=12 (4 kiB blocks on disk), the common case of a 4 kiB page size means
# that no compression algorithm can reduce I/O. The exception is all-zero pages, which are dropped by ZFS; but some form of compression has to be enabled to get this behavior.
zfs create -V 4G -b $(getconf PAGESIZE) -o compression=zle \
      -o logbias=throughput -o sync=always \
      -o primarycache=metadata -o secondarycache=none \
      -o com.sun:auto-snapshot=false omega/swap
mkswap -f /dev/zvol/omega/swap
## ADD SWAP TO FSTAB?  WHAT ABOUT THE WHOLE "AUTO DISCOVER MOUNTPOINTS" STUFF THAT SYSTEMD WAS PROMOTING FOR SINGLE-OS COMPUTERS?  SPECIAL UUIDS OR SOMETHING?
# The RESUME=none is necessary to disable resuming from hibernation. This does not work, as the zvol is not present (because the pool has not yet been imported) at the time the resume script
# runs. If it is not disabled, the boot process hangs for 30 seconds waiting for the swap zvol to appear.
echo RESUME=none >/mnt/etc/initramfs-tools/conf.d/resume
#swapon /dev/zvol/omega/swap     # to test it


######################################################################
### We need to activate zfs-mount-generator. This makes systemd aware of the separate mountpoints, which is important for things like /var/log and /var/tmp. In turn, rsyslog.service depends on

mkdir etc/zfs/zfs-list.cache
touch etc/zfs/zfs-list.cache/omega
ln -s /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh etc/zfs/zed.d  # ????
chroot . zed -F &
# Verify that zed updated the cache by making sure this is not empty:
cat etc/zfs/zfs-list.cache/omega
# If it is empty, force a cache update and check again:
zfs set canmount=noauto omega/root
pkill zed
# Fix the paths to eliminate /mnt:  [TWB: UGGGGGGH]
sed -ri "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/omega


# Snapshot the initial installation:
zfs snapshot omega/<all the "OS" and none of the "user data" volumes>@install


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
