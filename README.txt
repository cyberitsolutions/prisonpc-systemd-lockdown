This package is the systemd equivalent of apparmor-profiles.
It adds systemd-based confinement to other daemons.
(You can and should *both* this and apparmor-profiles!)

For example, it says nginx can't read from /home and can't write to /etc.

For more information see debian/control § Description and
systemd/system/0-EXAMPLES/20-default-deny.conf.
