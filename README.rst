Overview
============================================================
• https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/systemd/system/0-EXAMPLES/

  Is a good place to start reading.
  Those are written for Debian 10 so a little dated.


Gotchas
============================================================
• Systemd confinement applies to the entire cgroup.
  If msmtpd.service fork+exec's /bin/cat, there's no way to say "run cat unconfined", like apparmor does here:
  https://salsa.debian.org/kolter/msmtp/-/blob/debian/1.8.23-1/debian/apparmor/usr.bin.msmtp#L81

• Lots of things settings implicitly turn on ``NoNewPrivileges=yes``, which
  breaks a lot of things (e.g. no setgid, so maildrop(8postfix) breaks).

• If a daemon calls ``/usr/sbin/sendmail``, it's hard to harden it
  unless you know whether that's provided by ``msmtp-mta``,
  ``postfix``, ``exim``, ``sendmail``, or what.
  Because all of those need different privileges.
  See https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/tree/main/systemd/system/0-EXAMPLES/ for discussion.

• If a daemon runs arbitrary hooks (e.g. ``smartd`` and ``zfs-zed``),
  those hooks could theoretically do anything, so it's hard to know
  what can reasonably be hardened.

• If a daemon uses libnss (i.e. basically all of them),
  the user might have installed a ``libnss-foo`` package that needs any arbitrary thing.

  • ``libnss-ldapd`` and ``libnss-sss`` need AF_UNIX in https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictAddressFamilies=
  • ``libnss-resolve`` et al probably need AF_UNIX *and* AF_NETLINK.
  • ``libnss-nis`` and ``libnss-nisplus`` run in-process so need AF_INET and AF_INET6 in https://www.freedesktop.org/software/systemd/man/systemd.exec.html#RestrictAddressFamilies= *and*
    conflict with any https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#IPAddressAllow=ADDRESS%5B/PREFIXLENGTH%5D%E2%80%A6
    Note that due to how upgrading works, many people have libnss-nis installed but not enabled.

  • ``libnss-pam`` (the old PADL implementation) was similarly fucky, but it's completely gone as at Debian 12 (yay!).

  Question: could libnss-nis provide a systemd generator that automatically adds ``IPAddressAllow=<the NIS server(s)>`` to every unit?  (Thanks to Mithrandir for the idea.)

  Question: could NIS / NIS+ users be told "sssd supports NIS/NIS+, you must use that in Debian 14+"?

• If a daemon uses libpam,
  the user might have installed a ``libpam-foo`` package that needs any arbitrary thing.

  • ``libpam-ldapd`` and ``libpam-sss`` as above.
  • ``libpam-fprintd`` probably conflicts with https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html#DevicePolicy=auto%7Cclosed%7Cstrict ?
    I haven't actually investigated yet.

  Question: is there a way to know which /etc/pam.d/* files a given frobozzd.service unit will use, and
  therefore could libpam-foo.so add its "I need X, Y, and Z" rules to only those .service units?

  Pathological example: libvirtd.service runs a VM in qemu, and qemu
  runs smbd because of the following in my-cool-vm.xml.  How would the
  /etc/pam.d/samba package know to add "allow X" rules to
  libvirtd.service::

    <qemu:commandline>
      <qemu:arg value="-net" />
      <qemu:arg value="-user,smb=/opt/share" />
    </qemu:commandline>

• Any ``dlopen()``-based plugin framework (e.g. gstreamer's) is the same class of problem as nss/pam, though
  the scope is narrower.  e.g. the number of packages providing gstreamer plugins is pretty small.

• If a daemon manages a bunch of different worker processes (like ``postfix`` and ``dovecot``),
  you can't write separate confinment policies for each worker.
  You have to write a policy that allows everything every worker needs to do.
  For example postfix includes a postgres client
  https://www.postfix.org/pgsql_table.5.html which might need to talk
  to an arbitrary IP address, even if the actual SMTP only needs
  ``IPAddressAllow=mail.example.com``.

  ``nfs-utils`` 1.4+ is an example where the individual workers are
  managed by systemd as separate units, liberally using ``.target``
  and ``PartOf=`` and ``Alias=`` to help keep the end user sane.

• https://www.freedesktop.org/software/systemd/man/systemd.exec.html#SystemCallArchitectures=
  and
  https://manpages.debian.org/bookworm/dpkg/dpkg.1.en.html#add
  are inherently at odds.

  If ``nginx.service`` has ``SystemCallArchitectures=native`` and you
  ``apt install nginx:i386`` on an amd64 system, it won't start.

  In testing, I found that savelog from ``binutils:i386`` worked fine, though, so
  maybe at least some *simple* programs can get away with this?

  UPDATE: that was because savelog is a shell script, and /bin/sh was still amd64.

  roehling observes:

    If your threat model allows access to qemu-user-static for an attacker,
    they can run pretty much any binary is if it were native, and
    the whole SystemCallArchitectures hardening becomes meaningless.


  mjg59 observes:

    My understanding of the threat is that compatibility syscalls (eg, x32 on amd64) are
    less well-tested than the local architecture syscalls, and
    so allowing apps to call them increases the risk -
    a compromised app that can make compatibility syscalls stands a higher probability of being able to elevate privileges,
    either in userland or to the kernel itself.
    Allowing qemu to translate syscalls from other architectures to the local syscall ABI doesn't increase that risk, so isn't a concern.
    The goal isn't to prevent code form other architectures from running,
    it's to reduce the attack surface by preventing calls to the compatbility syscalls.


• Question: how do we make it as obvious as possible when a daemon crashes due to a ``deny foo`` rule?
  For example, when I tested nginx:i386 with SystemCallArchitectures=native, there was **NO** indication in journalctl or coredumpctl that it failed because it was i386.
  If I had just installed nginx:i386 and the Debian maintainer had put SystemCallArchitectures=native there, how the fuck would I have known that was the cause of the problem?

• Question: if we harden frobozzd.service by default in a way that breaks things for people who do X, how do we get a feel for how many people do X?
  e.g. in the SystemCallArchitectures=native case, how many people do ``dpkg --add-architecture``?
  Versus how many people will be protected by that, since it prevents i386 rootkits from executing (i.e. how many people were hit by i386 malware?).


History
============================================================
My original plan (circa 2018) was that this would be a simple
``Architecture: all`` package, and you could simply do ``apt install
more-security`` to lock down any packages you happened to have
installed.

This was modelled after apparmor-profiles and the idea was it'd let me
lock down a LOT of stuff without having to have a separate argument
"is this really necessary?" with each daemon's developer and/or
package maintainer.

Since then (2020-2023), I

1. moved all my in-production systemd hardening rules into
   https://git.cyber.com.au/cyber-ansible -- which is private, sorry.
   I also have a small amount buried in https://github.com/cyberitsolutions/bootstrap2020/

2. started hassling individual upstreams:

   • https://bugs.debian.org/929256
   • https://bugs.debian.org/984998
   • https://bugs.debian.org/996927
   • https://bugs.debian.org/1020328
   • https://bugs.debian.org/1024973
   • https://bugs.debian.org/1024975

So this repo kinda stopped getting updates.

Since then (2023), Russell Coker independently proposed a general hardening cleanup:

• https://lists.debian.org/debian-devel/2023/07/threads.html#00030


Adding more hardening
============================================================

What to harden (prioritization)
------------------------------------------------------------
• Start with daemons that are widely installed?

  https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/debian-systemd-service-units-by-popcon-popularity.tsv

  https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/contrib/units-by-popularity.py

• Start with daemons with a track record of insecurity?

  https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/debian-systemd-service-units-by-cve-count.tsv

• What units aren't even systemd-ized *at all* yet?

  https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/contrib/pre-koolaid-packages.py

  https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/contrib/pre-koolaid-packages.csv

• Start with daemons that have a well-defined "do one thing, well" mission?

  For example, ``e2scrub`` and ``ntpsec-rotate-stats``.

• Anything that has hooks/scripts, sends mail, is a "master" process manager, or otherwise in the Gotchas_ list... do later?

• Anything like ``sshd`` probably can't be done at all (since user login processes are part of the ssh unit)?

• Anything that has ``DefaultDependencies=no`` is probably pretty hairy... do later?

• Anything that has is part of ``src:systemd`` itself is probably already hardened as much as possible?  (e.g. systemd-udevd, journald)?

• Anything that ``systemd-analyze security`` says is already pretty good... do later? (e.g. mariadb)

  https://mariadb.com/kb/en/systemd/#useful-systemd-options


How to harden
------------------------------------------------------------
Once you've done 2-5 daemons, you get a "feel" for the trouble spots.
Total time to harden a unit from EXPOSURE=10 to EXPOSURE=3 usually takes me 1-4 hours.
If I've used the daemon before & know its config format & source code, usually 1 hour.

I typically start with a "deny all" ruleset.
Either I copy-paste from another daemon I did earlier, or
I copy-paste from ``systemd-analyze security``.
A slightly out-of-date one is
https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/systemd/system/0-EXAMPLES/20-default-deny.conf

Usually the daemon segfaults immediately.
In ``coredumpctl`` I see what the last syscall was.
Typically it is setuid so per I know to allowlist these::

    SystemCallFilter=@setuid
    CapabilityBoundingSet=CAP_SETUID CAP_SETGID

This is because the daemon does a no-op setuid(123) even if it's ALREADY 123 (due to User=%p in frobozzd.service).
This could be patched away, but so far my policy has been
"focus on stuff that doesn't require patching", so
instead I just allow that syscall.

It is very common to need both AF_UNIX and AF_NETLINK, so I don't even try to block those.
Things that need network (e.g. postfix, nginx) would also need AF_INET, AF_INET6, IPAddressAllow=all, &c.

The next most common failure is being unable to write to somewhere due to ProtectSystem=strict,
so I look for things like /run/frobozzd.pid or /var/lib/frobozzd/state.db in the error logs (journalctl -u frobozzd).
If systemd's existing things like RuntimeDirectory=%p aren't enough to cover it, I add ReadWritePaths=, or
downgrade ProtectSystem=strict to ProtectSystem=yes.

If it's still crashing, I remove ``SystemCallFilter=~@privileged @resources`` and ``CapabilityBoundingSet=`` entirely.
If that works, I strace or bisect to find which syscalls must be allowlisted.

If it's *STILL* crashing, I bisect over the entire hardening denylist.
(Comment out half.  Does it work now?  If so, it's mad about the commented-out half.  Repeat.)


The hardest part is the rare case where a daemon will automatically detect that an action failed, then
*silently* switch to a less-secure mode.
It is very hard to spot this is happening until after the hardened unit has been in production for a month or two.


PS: I typically have a dev loop like::

      journalctl -fu frobozzd &

      while ! systemctl restart frobozzd;
      do systemctl edit frobozzd; done

Or if it's on another host::

      M-! <hardening.conf ssh root@test '
          cat >/etc/systemd/system/frobozzd.service.d/hardening.conf;
          systemctl daemon-reload;
          systemctl restart frobozzd;
          systemctl status frobozzd'

PPS: so far I've been talking about system units, but
user units can also have hardening!

For example, I bet this only needs write access to /sys/blah/rfkill, and
could have it's TCP privileges revoked::

   org.gnome.SettingsDaemon.Rfkill.service 9.8 UNSAFE 😨

Also by default ``systemd-analyze security`` doesn't mention timer/path-fired units like e2scrub or fsck.
If you want to see those you have to do something like ``systemctl list-units --all --type=service``.


Adding a lintian hook
============================================================
I worked out to invoke it in offline mode (for lintian) you do this::

      systemd-analyze --offline=yes ./path/to/foo.service

I didn't understand (from the manpage) that I could pass a file instead of a unit name, so
I wasted a lot of time trying to make a minimal --root=tmpdir work.
Also it won't accept "./debian/service", nor a symlink to same.


Suggestions for upstreams
============================================================

• Being able to use ``RuntimeDirectory`` et al simplifies things.
  In particular it's easier to harden if your pidfile is either optional, or lives in ``/run/X/X.pid`` *not* directly in ``/run/X.pid``.

• Allow talking to smtp://localhost instead of /usr/sbin/sendmail.

  • For python programs this is pretty easy.
  • I don't have a good answer for C programs.
  • As an end user / sysadmin, I can just use msmtp to turn /usr/sbin/sendmail into an smtp call,
    e.g. https://github.com/cyberitsolutions/prisonpc-systemd-lockdown/blob/main/systemd/system/0-EXAMPLES/30-allow-mail-postfix-via-msmtp.conf

    This is probably too messy for Debian to do by default, though.
