2019-05-14 #systemd::

    16:17 <twb> OK so suppose I have a legacy PHP/Maria app that I want to jail, so that when it gets pwned, the attacker can't break anything else.
    16:17 [b1tninja likes twb's ventures with systemd]
    16:17 <twb> Plan B is qemu with kvm and virtio turned on.  Plan A is to use systemd's container/machined/nspawn stuff, similar to the old OpenVZ
    16:18 <twb> My key goal here is that -- assuming (pretending) the attacker can't pwn the shared kernel --- there is no way for the pwned PHP user to mess with anything running outside the container.
    16:18 <b1tninja> was going to suggest nspawn. I swear I recall some sort of inetdish functionality, use case was isolating ssh sessions
    16:19 <b1tninja> let me see if I can dig that u
    16:19 <twb> That includes things like "use up all the disk I/O so there is none left for ntpd"
    16:19 <grawity> b1tninja: that's still just regular nspawn that's autostarted, isn't it
    16:19 <twb> So my initial question is: what's the "starting point" manpage/doc that I should be reading?
    16:19 <b1tninja> think it was yes
    16:20 <grawity> I think there was an associated blog post about `systemd-analyze security <unit>`
    16:20 <twb> ssh to regular users get their own slices by default, as long as you enable PAM in sshd
    16:21 <twb> grawity: my systemd doesn't seem to have "systemd-analyze security" :-(
    16:21 <twb> Oops.  typo.
    16:22 <b1tninja> http://0pointer.de/blog/projects/socket-activated-containers.html wasnt the particular article but eh
    16:22 <twb> grawity: cool, that analyze security thing is SUPER HANDY.
    16:22 <twb> I tested it on systemd-timesyncd.service, since that's pretty anal by default
    16:22 <grawity> https://a.uguu.se/HBbQzlmC5kET.png most of my system is unhappy :(
    16:22 <twb> By comparison, ntpsec.service is mostly BALLOT CROSSes
    16:23 <grawity> well, they trust their own code that much
    16:23 <twb> grawity: rather, it just means that whoever wrote their unit didn't know about all the "bonus" lockdowns that systemd can add
    16:23 <twb> just like they don't have an apparmor profile yet
    16:24 <twb> How come systemd-timesyncd doesn't have PrivateUsers=
    16:25 <grawity> probably related to it having had DynamicUsers earlier, which Did Not Work Out
    16:25 <b1tninja> does user locale maybe come into play too
    16:26 <grawity> maybe it could have PrivateUsers= now that the latter has been disabled
    16:26 <grawity> b1tninja: the system clock is not dependent on user locale
    16:26 <twb> do you mean PrivateUsers + DynamicUsers didn't work out?  Or that the very idea of DynamicUsers was dumb?
    16:26 <grawity> the latter
    16:26 <twb> haha
    16:26 <grawity> well, it's just that *I* think the very idea of DynamicUsers was dumb
    16:26 <twb> I agree
    16:26 <b1tninja> woah https://www.freedesktop.org/software/systemd/man/systemd.exec.html#SystemCallFilter= is cool
    16:26 <twb> At least, I think it is a lot of risk for little benefit
    16:26 <grawity> but for timesyncd, it was more about a core systemd service / an early boot service
    16:27 <grawity> something about accidental loops, dependency on dbus, etc
    16:27 <b1tninja> dnssec blocking timesync when hostnames require it is an annoyance I have currently
    16:27 <grawity> and well, core systemd components just literally don't need a dynamic uid, so it was disabled
    16:28 <grawity> ah yeah, the ntp <=> dnssec problem isn't limited to systemd, you can get it pretty much everywhere
    16:28 <b1tninja> no chance someone knows how to downgrade dnssec when out of sync for timesync or something
    16:28 <grawity> openbsd has a time-from-TLS thing, google has Roughtime
    16:28 <b1tninja> presumably resolved has a way to allow dnssec for bootstrapping/resolving/verifying cert chains
    16:28 <twb> → Overall exposure level for gpg-agent.service: 9.7 UNSAFE 😨
    16:29 <grawity> twb: most of those options don't really work in per-user units, since AFAIK they're privileged operations
    16:29 <twb> Fair point
    16:29 <twb> systemd-analyze security $(systemctl list-units -t service | awk '/\.service/{print $1}') | grep Overall | sort -t: -nk2
    16:29 <twb> Everything except systemd-* is 8.3 or higher
    16:30 <grawity> (besides, gpg-agent is a secrets holder, it doesn't need to be contained from escaping but the other way around)
    16:30 <twb> I'm curious if more pro-systemd distros like fedora and arch have stronger default there
    16:30 <twb> grawity: contain ALL THE THINGS!  >rawr!<
    16:30 <grawity> lol just run `systemd-analyze security | awk '{print $2}'`
    16:30 <twb> Debian's package checker (lintian) is smart enough to complain if you provide a unit with no lockdown options
    16:30 <twb> grawity: oh thanks.
    16:31 <twb> grawity: I tried running it without arguments early on, but messed up
    16:31 <grawity> arch does not modify upstream units unless it just doesn't work otherwise
    16:34 <b1tninja> kvm would potentially seperate / isolate memory at a hw level in some cases, but more mgmt and resource usage, and attack surface i guess-- but usermode networking might be neat
    16:35 <b1tninja> id still opt for nspawn though

    17:23 <twb> OK so re my own questions, it looks like full containers that systemd "knows about" have their rootfs at /var/lib/machines/frobozz and you enable machines.target and systemd-nspawn@frobozz.service
    17:24 <b1tninja> you could maybe bind ro parts of your system
    17:24 <b1tninja> to avoid second install
    17:24 <twb> and to customize the start options you edit /etc/systemd/nspawn/frobozz.nspawn
    17:24 <twb> b1tninja: I tried that earlier and systemd-nspawn got really mad at me
    17:24 <twb> b1tninja: it was all like "no you can't have / as your rootfs!"
    17:25 <b1tninja> hm intersting
    17:25 <b1tninja> maybe bind specific subs
    17:25 <Exec1N> ok raw number of seconds worked for me
    17:25 <twb> b1tninja: maybe if I do more complicated binding than just "whatever is on / already"
    17:25 <b1tninja> i wonder if the utility path starts function checks empty string against empty string in that case
    17:26 <twb> b1tninja: one of my straightforward goals is to have a host with one NIC, four static IP addresses, and systemd-resolved, nsd3, unbound, and samba DNS servers each binding to :53 on *one* of those IP addresses, and ideally not even able to see the other addresses
    17:26 <b1tninja> wonder if you could have a refrence set like binds in your fstab under var lib machines
    17:26 <b1tninja> and use that
    17:26 <twb> b1tninja: PrivateXXX= are de-facto a list of bind mounts
    17:27 <twb> b1tninja: for .exec units; I'm not sure about .nspawn stuff
    17:27 <b1tninja> the localhost in ns is the one thing that was kinda a gotcha
    17:27 <twb> b1tninja: apt install libnss-myhostname
    17:27 <b1tninja> re net ns
    17:27 <b1tninja> lo
    17:27 <twb> b1tninja: that makes localhost always resolve, without any /etc/hosts
    17:27 <twb> it's part of the systemd codebase
    17:28 <b1tninja> was thinking for the container-host interactions
    17:28 <b1tninja> if you were going to redirect/nat etc
    17:31 <twb> b1tninja: the other annoying thing is that even though btrfs has lost and zfs has won, systemd nspawn/machinectl only have Bonus Magic for btrfs.  On the RFE, Lennart said it was because systemd will not support things that aren't in the mainline linux kernel.
    17:32 <b1tninja> I have personal affliction with btrfs
    17:32 <b1tninja> really like the nspawn unionfs stuff
    17:32 <twb> I run both
    17:33 <b1tninja> i had something to mention re the memory stuff but i totally forget
    17:38 <twb> are systemd nspawn containers typically "full" containers, of the sort that debootstrap makes?  Or are they more like "just copy /usr/bin/httpd to /init and install the 10 libfoo.so files it needs, and NOTHING ELSE"
    17:39 <twb> It seems like both kinds are more-or-less supported, but actually creating them is "out of scope" for the nspawn docs
    17:39 <boucman> twb: they are meant to launch systemd, but they work well with light containers too
    17:39 <boucman> yes creating them is out of scope
    17:39 <boucman> (I use buildroot for that)
    17:40 <b1tninja> a generator for such a thing would be neat
    17:40 <b1tninja> you've seen machinectl i assume
    17:40 <boucman> buildroot is a generator for that, so is  yocto, so is debootstrap....
    17:41 <boucman> (well, for the light version I 'm not sure debootstrap could do it)
    17:41 <twb> debootstrap creates a relatively heavyweight container, though
    17:41 <twb> It effectively ALWAYS requires apt inside the rootfs
    17:41 <boucman> we are writing the necessary bits at my company to have BR generate portable containers right now
    17:42 <twb> I think what I want is closer to how dracut and initramfs-tools build their ramdisks
    17:42 <twb> Or not necessarily *want*, but at least asking about
    17:43 <boucman> I won't blame you for not knowing what you want, the terms in the container space are a mess
    17:43 <b1tninja> arch had a "mkarchroot"
    17:44 <twb> My background is with hand-made lxc containers, libvirt or hand-made qemu kvm VMs, and hand-made squashfs live images
    17:44 <boucman> I don't think any non-embedded distro have tools that can reliably make light containers... honestly I only know BR and docker that can do that, and docker's way is a tracability nightmare
    17:44 <twb> I've avoided all the docker/rkt stuff because they don't seem to really have a handle on security yet
    17:45 <b1tninja> i avoid it too, waiting for the container war to settle down
    17:45 <twb> boucman: OK, I'll start with the one for making debian ramdisks that never switch_root ;-)
    17:49 <twb> Found it: https://packages.debian.org/buster/debirf
    17:45 <boucman> honestry, try buildroot, it's really trivial to understand, and it works wonders
    17:45 <b1tninja> this dudes tool was kind of neat https://github.com/tlahdekorpi/archivegen
    17:45 <twb> boucman: isn't that the one you wrote yourself? ;-)
    17:45 <boucman> huh ? no
    17:45 <boucman> I never wrote any tool like that
    17:45 <twb> Never mind, I must be thining of someone else.
    17:46 <boucman> it's a classic, well established tool in the embedded world, it's been around for a decade or so IIRC
    17:46 <twb> Oh, THAT one
    17:47 <twb> I've used the OpenWRT equivalent before
    17:47 <boucman> yes, but openwrt is very specialized, it really works well for routers only... I don't think it's the right tool for light containers
    17:48 <twb> granted
    17:51 <b1tninja> something that maybe looked for executables under a path and grabbed shared libs would be nice
    17:51 <twb> b1tninja: dracut does that :-)
    17:51 <b1tninja> nice
    17:52 <twb> The way dracut and (older) initramfs-tools basically work is you say "I need bash inside the rd" and it goes "OK, copy /bin/bash, and also anything mentioned in ldd /bin/bash"
    17:52 <twb> Then if your bash has a security update, you just rebuild the ramdisk
    17:52 <boucman> that gives you no tracability on what's on your system... I don't know your use-case, but I usually need to know exactly what's on my image for license/security reasons...
    17:53 <twb> boucman: in my use case, the host OS and the container will be fed from the same repo, so I don't care
    17:53 <boucman> ok
    17:53 <twb> boucman: like, I'm not building a static "container image" and then carrying it off to another place to run it
    17:53 <twb> It's more like dracut's "use whatever the host already has"
    17:54 <twb> At least, that's ONE idea I'm CONSIDERING.
    17:54 <b1tninja> ima have to play around with it more but i want a bind ro'd php env now =p so just update the system, but guess maybe legacy apps might want an old version
    17:54 <twb> b1tninja: I have definitely done that 10 years ago with lxc
    17:54 <b1tninja> wonder if there is like a follow symlinks dealio
    17:54 <b1tninja> "flatten symlinks" etc
    17:54 <twb> b1tninja: a straightforward case was something like "run dhclient with a netns but the same rootfs, then see if it gets a different IP address"
    17:55 <b1tninja> client identifier ;p
    17:57 <b1tninja> (systemd-firstboot --setup-machine-id) etc
    17:57 <twb> yeah, these days you'd need to worry about all that crap
    17:57 <b1tninja> wish they hadn't made client id the default >_>
    17:58 <twb> Huh, debirf knows about systemd-networkd, so it can't be as old as I thought
    17:59 <b1tninja> you saw --overlay and --overlay-ro
    18:00 <twb> not yet
    18:08 /join #archlinux
    18:15 <killermoehre> twb: also looked at --volatile?
    18:16 <twb> killermoehre: aha!
    18:16 <twb> killermoehre: I have seen that before, long ago, and forgotten about it
    18:17 <twb> Ah, I would have been looking at that in the context of live CDs, as an alternative to live-boot-initramfs-tools's union mounts
    18:17 <b1tninja> and maybe shutdown /var =p
    18:25 <twb> hahaha --kill-signal reminds me how every init has its own preferred signal for "let's turn off now"
    18:26 <b1tninja> shutdown kills itself >_>

2019-05-15 #systemd::

    16:25 <twb> does "machinectl import-tar" do anything other than tar -x ?
    16:37 <twb> the source in machined-core.c is hard to follow
    16:37 <twb> It appears to just be doing "tar - < foo.tar"
    16:38 <twb> debspawn creates a running container directly using systemd-nspawn.  machinectl can see it.  machinectl can't clone it.  Why not?
    16:39 <twb> http://ix.io/1J5R
    16:48 <twb> What's the equivalent of "systemctl show" for a .nspawn?
    16:48 <twb> "machinectl show" seems to work, as long as the container is actually running
    16:49 <twb> it doesn't list all the fun stuff in the .nspawn though
    17:30 <robert_> huh
    17:35 <robert_> twb: https://gist.github.com/f1fa2ce46ac5af0732014ac6d2d1d1a4
    17:39 <twb> Can I configure how quickly StopWhenUnneeded= gives up?
    17:48 <twb> GRARGH.  I'm trying to use https://github.com/systemd/systemd/issues/2741  to constrain nsd.service
    17:49 <twb> nsd.service needs PrivateTmp=yes, or it crashes.
    17:49 <twb> netns@.service needs PrivateTmp=no, or it crashes.
    17:49 <twb> nsd.service JoinsNamespaceOf=netns@foobar.service is therefore not possible!
    17:51 <twb> My end goal is to run unbound.service and nsd.service, each with a private network that can see eth0 but only one address on eth0.
    17:51 <twb> (Which might be a very silly thing to want; I'm not sure yet)
    17:53 <twb> I suppose what I could do is ExecStart=! for the netns@ lines...
    17:56 <twb> That's just making ip(8) core dump :-(
    17:58 <twb> It's =+ not =! now, but PrivateTmp still affects those
    17:58 <twb> So... blech
    18:12 <boucman_work> twb, I think there is a type of virtual device you could use for that, rather than assigning multiple IP to eth0, you make multiple interfaces all of which ar physically on eth0
    18:12 <boucman_work> and then you give one interface to each NS
    18:14 <boucman_work> (and to answer your question, this is more a support channel than a dev channel, you'd better redirect that question to the mailing list and/or github, the core systemd devs are more active there)
    18:14 <twb> boucman_work: do you know how to actually "give" an interface to a namespace?
    18:14 <twb> boucman_work: I suspect that if I don't care about "named" netns's (for ip netns xxx), I can bring up the ifaces/addresses via systemd.netdev.  But I don't really know what I'm doing here.
    18:14 <boucman_work> twb, with "ip" yes... there is also a nspawn parameter for that.... for a service, I'm not sure.
    18:15 <boucman_work> named netns is an ip thing, not a kernel thing iirc, but network is not my forte...
    18:16 <twb> boucman_work: I agree re named netns
    18:17 <twb> "ip link add veth-twb type veth" does... something
    18:25 <boucman_work> the notify socket is passed from the host systemd to the container systemd, so the container systemd will pet the host-systemd, which in turn pets the hardware watchdog
    18:26 <boucman_work> which also means that the status of containers is properly followed. While the container-systemd is booting, the host-systemd will mark it as starting and only when the container-systemd reports that it is ready will the host-systemd mark the service as ready
    18:27 <boucman_work> so syncing with After= on containers will work as expected
    18:28 <boucman_work> yes and no
    18:30 <twb> boucman_work: OK so what the guys in that issue seem to be doing is creating two "veth" ifaces, which are basically two fake ethernet ifaces glued together.
    18:30 <twb> boucman_work: then on the outside, they bridge/nat/tunnel/whatever veth-OUTSIDE@veth-INSIDE to en0
    18:31 <twb> boucman_work: then on the inside, they add 1.2.3.4/24 and 0/0 via 1.2.3.1 to veth-INSIDE@veth-OUTSIDE
    18:31 <boucman_work> systemd-nspawn implements it (systemd-nspawn is very systemd-aware) but it's "just" about passing an opened socket to the container-init+setting an environment variable
    18:31 <twb> *I think*
    18:31 <twb> boucman_work: yeah but nspawn expects an entire container, not just 1 or 2 services
    18:31 <boucman_work> both of which are already passed/set by systemd
    18:32 <twb> It's not clear to me how I can say "dear nspawn, please run nsd.service with these nspawn options"
    18:32 <boucman_work> twb, I was answering auxloop (which has a full container iiuc)
    18:32 <twb> oh sorry
    18:32 <boucman_work> np
    18:33 <boucman_work> twb, for you, veth are probably not the right type of virtual interfaces, they create a pair of connected interfaces, but they are not linked to a "real HW" interface...
    18:34 <boucman_work> but there are so many types of virtual interfaces in linux that I'm not sure what would be the right one... I know it exists, but I don't know what it's called
    18:35 <twb> systemd.netdev has a list
    18:36 <twb> ipvlan maybe
    18:36 <boucman_work> yeah, that sounds about right
    18:36 <boucman_work> test it manually first, though
    18:37 <twb> Even if I spin that up in systemd-networkd, I don't see how to "share" it into the PrivateNework='d .service
    18:39 <twb> Oh wow, LogLevelMax= is new and cool
    18:40 <twb> (since v215)
    18:40 [Xogium blinks]
    18:40 <Xogium> so its not that new :p
    18:41 <twb> v215 was the last time I went through *every* option in systemd :P
    18:42 <Xogium> hahahah I do it at every release
    18:43 <twb> AppArmorProfile= says the profile "must already be loaded into the kernel".  Does systemd implicitly add an After= on the units that set up apparmor profiles?  The manpage doesn't say so.
    18:47 <boucman_work> I'd say "try and see what happens :) )
    18:48 <twb> from RTFS, it doesn't look like it
    18:48 <boucman_work> but having systemd pet systemd would probably have more chance to be upstreamed than implementing a different watchdog mechanism...
    18:48 <twb> So on a "normal" system, I guess if AppArmorProfile=usr.bin.foo is used, I have to also add Requires= and After= on ... apparmor.service, I guess
    18:50 <grawity> boucman_work: huh, it seems like a feature that should have been there the whole time
    18:50 <grawity> twb: only if your unit has DefaultDependencies=no
    18:50 <grawity> because apparmor.service does have this option and Before=sysinit.target, while normal services are after sysinit
    18:51 <twb> grawity: ah, good catch
    18:51 [grawity thought apparmor profiles are selected automatically based on the executable name]
    18:52 <boucman_work> grawity, it might be already there (that was my understanding) but I am not sure, so I can't be very affirmative about it
    18:56 <twb> grawity: yeah but that only applies to the main binary, I think
    18:56 <twb> grawity: I think the idea is that if you use AppArmorProfile= it can lock down all the ExecStartPre= crap
    18:56 <twb> grawity: that's just a guess, though

    19:50 <twb> Where do you set blackhole routes for private-use address ranges in systemd-networkd?
    19:50 <twb> This is how I used to do it: http://ix.io/1J6E
    19:51 <grawity> maybe [Route] Destination=10.0.0.0/0 Type=unreachable
    19:51 <twb> Type=blackhole exists within .network
    19:51 <twb> But systemd-networkd doesn't manage the lo iface, at least on Debian 10
    19:51 <twb> Maybe I can/should just continue putting them in /etc/network/interfaces, on the lo iface...
    19:51 <grawity> well
    19:51 <grawity> where do you set up the default route?
    19:52 <grawity> the problem doesn't exist when you do not have a default route yet
    19:52 <grawity> so the natural place would be eth0.network or something such
    19:52 <twb> grawity: default route is set up on one or more ethernet interfaces
    19:52 <grawity> "or more"?
    19:52 <twb> grawity: for when I have multiple upstreams for failover reasons
    19:52 <twb> You put a "throw" rule in the default route table, and use firewall marks to send responses over the correct uplink
    19:53 <killermoehre> twb: wouldn't you solve multiple upstreams with a team-device or appropriate metrics?
    19:53 <twb> But yeah, I could probably just shove them in the single upstream.network that I have in most systems
    19:54 <grawity> killermoehre: team/bond only works with multiple identical links (i.e. gives you a single fat cable)
    19:54 <twb> killermoehre: http://cyber.com.au/~twb/doc/dual-uplink.txt
    19:54 <grawity> twb: add the routes in *all* .network files
    19:54 <twb> grawity: hrmmmm
    19:55 <grawity> in my config, I create a dummy0.netdev for reasons, so I'd be placing such rules there
    19:55 <twb> grawity: the routes aren't link-local by default, though
    19:55 <grawity> (although I already have BIRD routing daemon to handle that for me, but otherwise)
    19:55 <grawity> twb: they don't have to be, do they
    19:55 <twb> if you have (say) an uplink.network and a downlink.network, and BOTH of them define the same blackhole routes, then if EITHER link goes down, won't networkctl drop the blackholes?
    19:55 <grawity> hmm I don't see why
    19:56 <twb> because it would remove routes as part of its teardown
    19:56 <twb> (surely?)
    19:56 <grawity> not if it knows that the same route is defined by another device
    19:56 <twb> Oh OK
    19:56 <grawity> which I hope it does
    19:56 <twb> I didn't expect it to be that smart :P
    19:57 <grawity> the advantages of having a central daemon instead of a collection of shellscripts?
    19:58 <grawity> hmm that 'throw default' trick might be useful
    19:58 <twb> yaaaaaay learing
    19:58 <twb> *learning
    19:59 <twb> In other news, *something* created ve-<hostname> and networkctl says it's no-carrier configuring
    19:59 <twb> But it's not mentioned in /etc/systemd/network/
    19:59 <grawity> sounds like a nspawn thing
    20:00 <grawity> the host end of a veth pair
    20:00 <twb> Oh, /lib/systemd/network/80-container-ve.network
    20:00 <twb> Anyway, possibly because of that, when I force-reload systemd-networkd, it tells me wait-online will never happen, which makes me cranky.
    20:00 <twb> systemd-networkd-wait-online[21108]: Event loop failed: Connection timed out
    20:00 <twb> systemd[1]: Failed to start Wait for Network to be Configured.
    20:01 <killermoehre> twb: you want probably your own wait-online.service
    20:01 <twb> Can't I just tell it not to care about the ve-* thing?
    20:01 <twb> Its logs suggest it's already ignoring lo
    20:02 <twb> Oho, /lib/systemd/systemd-networkd-wait-online --help says it has --ignore
    20:05 <twb> Also, I just realized it's named after one of the nspawn'd hosts, rather than after the host OS.  So now I understand what's going on better.
    20:06 <twb> If I "machinectl stop not-alamo", systemd-networkd-wait-online completes immediately
    20:07 <twb> http://ix.io/1J6K  you can see the ve getting confused during "machinectl start"
    20:08 <twb> But that's probably my fault for not setting up the /var/lib/machines/not-alamo/ tree the way machined expects
    20:08 <grawity> networkd could use some verbosity by default imho
    20:12 <Xogium> so could timesyncd… Doesn't even signal a dns resolution failure of any kind and just reports idling away when checking the status… I had to run ntpd to understand it was dnssec failure every time
    20:12 <grawity> though lennart will of course just say "yeah and I'd like a pony"

2019-05-16 #ntpsec::

    19:56 <twb> Why isn't /usr/lib/ntp/rotate-stats just /etc/logrotate.d/ntpsec ?
    21:10 <twb> Woo, using rotate-stats as my test for "tell systemd to lock down all the things", and the script is still correctly gzipping and find -delete'ing.
    21:10 <twb> http://ix.io/1JcP

2019-05-16 #systemd::

    16:23 <twb> Can I "systemd analyze security" an ordinary file, that I haven't installed into a running systemd yet?
    17:15 <jelle> twb: man page mentions [unit...] not a regular file
    17:15 <twb> jelle: yeah thanks.  I thought there might be some way I hadn't seen
    17:16 <twb> The use case was comparing lockdown between e.g. competing MTAs, where I can't install >1 at a time.
    17:17 <twb> Or doing a bulk check of all the units in Debian, without installing anything
    17:17 <jelle> well you can always lock them down yourself
    17:17 <twb> jelle: yeah granted.  I want to know which upstreams had already made an effort
    17:17 <twb> Becaues if they have, they probably care about security in general
    17:17 <jelle> I wouldn't agree :p
    17:18 <twb> haha
    17:18 <jelle> it's pretty new, and systemd files can also come from your distro
    17:19 <twb> granted
    18:21 <twb> When I'm locking down a unit, is there something like strace or audit to tell me all the things it TRIED to do?
    18:22 <twb> Like, my test case is an irc daemon, and with ProtectSystem=strict, some of its helper processes fail, but it's not immediately obvious WHY.
    18:34 <jelle> well strace -e open $process shows files it opens
    18:35 <twb> Yeah, adding that to the front of ExecStart= is basically plan B
    18:35 <twb> I was hoping you'd say "oh, use systemd-supercoolthing"
    18:35 <jelle> I wonder if systemd has thought of showing violations or even neater, analyzing a process and generating rules
    18:35 <twb> apparmor has a huge set of helper tools to help automate aa lockdown
    18:36 <twb> like, it's smart enough to do things like "hey, looks like this is doing DNS stuff, so I'll suggest @include dns-common"
    18:36 <twb> rather than just the individual specific things it saw the daemon doing while in complain mode
    18:43 <twb> OK so FYI, I re-remembered that I do like "aa-genprof /usr/bin/irssi", then in another window run irssi and do some stuff.  Then in the first window hit "s" and "f", and I have an /etc/apparmor.d/usr.bin.irssi example ruleset
    18:44 <twb> Which lets me see that it needs read access to /etc and write access to $HOME, for example, so ProtectHome= won't be its friend
    18:45 <twb> And it executed /bin/dash, so removing fork(2) won't work
    18:45 <twb> Oh.  Oh damn.  irssi already HAD an aa profile.  Let me try a different test program :-/
    20:35 <twb> How do I use SystemCallFilter=
    20:36 <twb> I'm doing a test lockdown of what is basically logrotate.sh
    20:37 <TheBrayn> man 5 systemd.exec has some more information on that
    20:37 <twb> http://ix.io/1JcB
    20:37 <twb> TheBrayn: yeah I'm reading that but I'm clearly too tired to understand what I'm doing wrong
    20:39 <twb> Oh maybe SystemCallFilter= isn't supported on this kernel
    20:39 <twb> let's look for that "herp derp no BPFs" message that timesyncd sometimes emits
    20:40 <twb> Can't see it...
    20:41 <twb> I have CONFIG_CGROUP_BPF=y at least
    20:44 <twb> Brainwave: look for existing SystemCallFilter= examples
    20:45 <twb> lib/systemd/system/nsd.service:SystemCallFilter=~@clock @cpu-emulation @debug @keyring @module mount @obsolete @resources
    20:45 <twb> systemd-analyze security claims that's unlocked, too
    20:45 <twb> All the other examples use a whitelist, not a blacklist
    20:45 <twb> e.g. lib/systemd/system/systemd-hostnamed.service:SystemCallFilter=@system-service sethostname
    20:46 <twb> "systemd-analyze security systemd-hostnamed" shows green for most (but not all) SystemCallFilter= lines.
    20:47 <twb> So WTF
    20:54 <twb> I used SystemCallFilter=@system-service for now, which is "90% right"
    20:54 <twb> I also noticed that "systemd-analyze security" is reporting that User= and PrivateUsers= aren't locked down, even though I've set them and they show up in "systemctl show"
    20:57 <twb> And I can see from the files it's creating that it's definitely running as User=
    20:59 <killermoehre> hmm, intersting problem: can I list a units with type X where property Y has value Z?
    20:59 <killermoehre> *all units
    21:00 <twb> killermoehre: I only know how to do that by brute force
    21:00 <twb> list-units | show | grep
    21:00 <killermoehre> twb: yeah, brute-force is easy. but something with busctl?
    21:03 <twb> ARGH.  I was doing "up up up ret" to check the systemd-analyze after editing
    21:03 <twb> But I was running the wrong command out of my history
    21:03 <twb> Now I run the right command, things work!
    21:03 <twb> → Overall exposure level for ntpsec-rotate-stats.service: 0.3 SAFE 😀

2019-05-16 #apparmor::

    19:13 <twb> Woo, I'm using aa-genprof like a grownup!
    19:13 <twb> This one looks funny, though: http://ix.io/1Jcm  isn't totem a video playing thing?
    21:20 <twb> FTR, abstractions/totem *is* the movie-playing thing
    21:21 <twb> No idea why it was suggested; I skipped past it and got to a point where the daemon was still segfaulting, but genprof wasn't finding any more auditd items, so I gave up for tonight

2019-05-20 #systemd::

    11:11 <twb> Does IPAddressAllow= control which addresses the unit can be a server for (listen on), or which addresses the unit can connect to, or both, or what?
    11:12 <twb> "Access will be granted in case its destination/source address matches any entry"
    11:12 <twb> ...makes it sound like as long as *either* end matches, it'll be allowed
    11:13 <twb> Hrm, so I can do something like "IPAddressAllow=10/8 127/8 IPAddressDeny=all" to allow it to reach anything on the LAN
    11:14 <twb> But I can't say something like "this host has ten IPs, allow unit X.service to LISTEN only on 10.1.2.3/32, but ACCEPT connections from anywhere"
    11:54 <twb> Is there an /etc/systemd/system.conf.d/override.conf, or do I have to edit system.conf directly?
    11:57 <twb> Is there something like systemd-cgls but for namespaces instead of cgroups?
    12:07 <deltab> newer versions of pstree can show namespace changes
    12:09 <twb> Hrm, diff -u <(pstree) <(pstree -S)
    12:09 <twb> Shows that e.g. dovecot has a "mnt" namespace, and systemd-nspawn has a whole bunch
    12:12 <twb> When I see this error, what have I done wrong?
    12:12 <twb> root@not-omega:~# machinectl login not-alamo
    12:12 <twb> Failed to get login PTY: Protocol error
    12:14 <twb> The container has started up just fine (via machinectl start not-alamo); the guest has systemd as pid1; not sure what else to check
    12:16 <twb> Hrm, there is *both* "login" and "shell" commands
    12:16 <twb> Same error, though
    12:25 <twb> To answer one of my earlier questions, systemd-system.conf says /etc/systemd/system.conf.d/*.conf is checked
    12:25 <deltab> does the container have dbus? https://github.com/systemd/systemd/issues/685
    12:26 <twb> deltab: good thinking!  Debian's systemd doesn't hard-depend on dbus for horrible reasons
    12:28 <twb> Does SystemCallArchitectures= affect people using qemu CPU emulation + binfmt-misc to run cross-arch chroots?
    12:28 <twb> e.g. an armv7 chroot on x86_64 hardware
    12:29 <twb> https://wiki.debian.org/QemuUserEmulation
    12:30 <twb> deltab: dbus was not installed
    12:32 <twb> "$ systemd-nspawn --machine not-alamo apt install dbus" didn't Just Work; seems it either can't resolve or can't connect to deb.debian.org :-(
    12:35 <twb> Looks like inside the container, nsswitch.conf and resolv.conf are only pointing at systemd-resolved, and systemd-resolved's backcompat listened on 127.0.0.53 is off because I'm running an authoritative nameserver on this host
    12:35 <twb> So installing libnss-resolve inside the container will probably fix it
    12:37 <twb> OK, after installing dbus, "machinectl login" works fine!
    12:38 <twb> "machinectl shell not-alamo" gives "sh: 2: exec: : Permission denied".
    12:38 <twb> Ah, I'm supposed to do something like this: "machinectl shell not-alamo /bin/cat /etc/passwd"
    12:43 <deltab> it seems the message was changed to "Failed to get login PTY: There is no system bus in container" -- do you have a pre-2016 version of systemd?
    12:44 <deltab> looks like IPAddressAllow works at the packet level, so it doesn't know about syscalls
    12:44 <twb> inside the container, yes
    12:45 <twb> host is Debian 10, guest is Debian 9
    12:45 <twb> deltab: so IPAddressAllow is basically a per-unit netfilter *filter table?
    12:46 <deltab> yeah, looks that way
    12:47 <twb> Is it possible to have a full nftables ruleset per-unit?
    12:48 <twb> (for doing fancier things, like, oh, rate limiting or port knocking)
    13:16 <deltab> I imagine so, tied to the network namespace, but I don't know how you'd set it up
    13:23 <twb> I tried using a PowerPC 64 chroot via qemu+binfmt, and SystemCallArchitecture didn't stop me
    13:23 <twb> http://ix.io/1JxB
    13:24 <twb> The use case for that is cross-compiling without having to spin up special any cross-arch packages, or a full VM, but sort of in-between
    13:35 <scientes> twb: you really need a real VPS
    13:35 <scientes> qemu for powerpc64 is not very good
    13:35 <scientes> at least when it comes to altivec
    13:36 <scientes> twb, 
    13:37 <twb> k.  That was really a thought experiment though
    13:37 <scientes> and clang is a native cross-compiler
    13:37 <scientes> so it is quite easy to cross-compile with clang
    13:38 <Xogium> qemu is no good for aarch64 either
    13:38 <twb> scientes: but then you have to deal with all the build depends and everything
    13:38 <scientes> debian can do it
    13:38 <scientes> but only to a certainly point necessary to bootstrap a new arch
    13:38 <scientes> ARM sponsored that work
    13:38 <twb> you mean like "apt install libfoo-dev:ppc64el" ?
    13:38 <scientes> for their AArch64 bringup
    13:38 <scientes> no, it can bootstrap itsself
    13:39 <scientes> dpkg-buildpackage supports cross-builds
    13:40 <twb> hrm
    13:41 <scientes> systemd probably cross builds with it (or use to) as it is important
    13:41 <twb> does systemd have a list of supported architectures?
    13:41 <twb> You know like how GNOME doesn't support s390 anymore because rust.
    13:42 <scientes> s390 works with llvm
    13:42 <scientes> well actually not sure, ppc64el certainly does
    13:42 <scientes> twb, systemd supports gcc and clang
    13:42 <scientes> and even the 486
    13:42 <twb> righto
    13:43 <scientes> (which is gcc-specific, clang can only build pentium 3+)
    13:43 <twb> insert joke here "it said pentium or better so I bought a sparcstation"
    13:46 <Xogium> too bad systemd can only be built with glibc
    13:47 <Xogium> uclibc-ng used to work, then they broke support for it, then they fixed it, then they broke it for good again
    13:47 <Xogium> and lets just not try with musl
    13:48 <twb> but but but musl has a UTF-8 LANG=C!
    13:49 <scientes> or you can just ignore that variable...
    13:49 <scientes> cause wide character support in libc is so funcky, systemd doesn't use it
    13:50 <Xogium> well, they planned on making that the default for a while and afaik its still the default
    13:50 <Xogium> you have to specify the C local now or its going to default to the utf8 variant
    13:51 <Xogium> which… Noone provides, afaik
    13:52 <scientes> environment variables are a really bad design anyways
    13:52 <scientes> they waste memory bad
    13:52 <twb> Xogium: AFAIK glibc/RH/Debian are working to clean up C vs. C.UTF-8 right now
    13:53 <Xogium> well, they'd better do it :D
    13:54 <Xogium> I mean, we're in 2019 lol
    14:45 <twb> Does "systemctl daemon-reload" cause system.conf to be reread?
    14:45 <twb> I guess I can just put a typo in it and see if I see a warning
    14:46 <twb> Rargh, my qemu test earlier was bogus!
    14:46 <twb> May 20 13:22:30 not-omega systemd[1]: /etc/systemd/system/qemu-versus-systemcallarchitectures.service:4: Unknown lvalue 'SystemCallArchitecture' in section 'Service', ignoring
    14:47 <twb> Ah, it's plural
    14:54 <twb> OK, SystemCallArchitectures=native is still not stopping qemu-user-binfmt, FYI
    14:55 <twb> Also, daemon-reload appears to have reread system.conf, because now the logs are getting "Consumed 31ms CPU time, no IP traffic." lines
    15:58 <twb> Hey!  journalctl -u foo can't see kernel auditd messages about foo!
    16:21 <twb> If I want to see the read-only vs. read-write vs. hidden of a given unit, do I look in /proc/<pidof daemon>/mountinfo?
    16:21 <twb> That certainly tells me... something
    16:22 <twb> It's hard to tell what's a bind mount, though
    16:23 <twb> http://ix.io/1JxW
    17:34 <twb> These options are pretty confusing - it has ro *and* rw, in separate places
    17:34 <twb> root@not-omega:~# grep -Fw --color -e ro -e rw /proc/$(pidof rsync)/mountinfo
    17:34 <twb> 1364 1281 0:21 / / ro,relatime shared:550 master:1 - zfs omega/ROOT rw,xattr,posixacl
    17:34 <twb> it's read-only in practice, though
    17:39 <twb> If I have a unit that wants to bind to a low port AND doesn't support socket activation, can I tell systemd to run it as User= but still give it CAP_NET_BIND?

2019-05-20 #dovecot::

    19:38 <twb> Anybody know offhand what capabilities and syscalls dovecot needs?
    19:39 <twb> systemd-analyze security dovecot | curl '-sSfFf:1=<-' ix.io  looks like   http://ix.io/1Jyn
    19:39 <twb> (That's systemd having a whinge about anything systemd isn't in charge of locking down)
    19:42 <cmouse> it's impossible to say exhaustively.
    19:42 <twb> No worries
    19:43 <twb> At the moment I'm just e.g. making /etc read-only and then waiting for complaints in the logs
    19:43 <twb> When I get it to a "near enough is good enough" state I'll push it upstream to Debian
    19:44 <cmouse> did you look at the default policy we ship with dovecot?
    19:45 <twb> I'm not sure what you mean by policy
    19:45 <cmouse> sorry i mean service unit
    19:45 <cmouse> https://github.com/dovecot/core/blob/master/dovecot.service.in
    19:45 <twb> I'm starting from whatever Debian ships, which is probably the same as what you ship
    19:46 <cmouse> for apparmor we provide 'apparmor'  plugin
    19:46 <cmouse> to make it less complicated to write policies.
    19:47 <cmouse> mostly it's for allowing to have a "hat" for accessing the user's mails
    19:47 <twb> confirmed, what you linked to is what I was starting from, which systemd considers to be "EXPOSED" (http://ix.io/1Jyn)
    19:48 <cmouse> sure.
    19:48 <cmouse> we could probably tighen things up more if we wanted
    19:48 <twb> It's broadly similar to an apparmor profile/selinux policy.  There's no changehat equivalent, though.
    19:48 <cmouse> yeah
    19:48 <twb> It's more stuff like "hey dovecot is never going to need to load kernel modules, so block that before it even asks"
    19:48 <cmouse> we had to drop e.g. NoNewPrivileges because that breaks things
    19:49 <cmouse> sure
    19:49 <twb> ah, that's good to know
    19:49 <cmouse> it is just difficult to validate which are breaking and which are not
    19:49 <cmouse> since dovecot can be ran in so many ways
    19:49 <cmouse> hm
    19:49 <twb> Yeah, I'm looking to get something that's like 80% locked down and handles 80% of use cases with no fiddling, and people who want more or less can tweak it
    19:49 <cmouse> we have ProtectSystem=full in our service block
    19:50 <twb> =full isn't as full as =strict ;-)
    19:50 <cmouse> i know
    19:53 <twb> the nice thing about this new "systemd-analyze security" thing is it prioritizes them by badness, so you can do the scariest ones first
    20:03 <twb> I think if NoNewPrivileges=yes breaks things, it would be good for the default unit to have a comment like "# NoNewPrivileges=yes broke XXX (ref. issue1234)", so there's a hint for the next person
    20:04 <twb> The hint at the top about dovecot.service.d/service.conf can mention "systemctl edit dovecot" which is new since about 2016
    20:05 <twb> I guess PrivateHome=no is needed for sieve and stuff, even if the actual mailboxes live in /var
    20:07 <twb> Also, this might be obvious to you already: Type=simple means other units (e.g. postfix) cannot wait for dovecot to be "ready" unless dovecot has sd_notify("READY=1") stuff baked into it.
    20:08 <twb> With Type=forking, systemd assumes when the double fork happens is when dovecot's "finished starting" and its dependencies can be spun up
    20:09 <twb> I guess it doesn't really matter, because if postfix can't talk to dovecot's SASL socket, it'll just reject a few messages, it won't actually *crash*...

2019-05-20 #apparmor::

    15:59 <twb> If upstream provides an apparmor profile for a binary, but it's a bit broken, can I store my fixes in a separate file?
    15:59 <twb> The immediate case is this:
    16:00 <twb> kernel: audit: type=1400 audit(XXX): apparmor="DENIED" operation="open" profile="/usr/sbin/apt-cacher-ng" name="/etc/ssl/openssl.cnf" pid=8216 comm="apt-cacher-ng" requested_mask="r" denied_mask="r" fsuid=108 ouid=0
    17:09 <jjohansen> twb: potentially. It depends on what you are trying to do, and how the profile is setup
    17:09 <jjohansen> you could of course always just replace the profile, obviously this isn't what you are asking
    17:09 <jjohansen> depending on the reason for the denial
    17:09 <jjohansen> its might be possible to extend the profile with an include.
    17:10 <jjohansen> eg. several profiles have an include of
    17:10 <jjohansen> /etc/apparmor.d/local/...
    17:10 <twb> with that whole local/ thing everyone seems to- that
    17:10 <jjohansen> which is a file you can locally edit
    17:10 <jjohansen> right
    17:11 <twb> Can I tell genprof to write there?
    17:12 <jjohansen> however, local can't override some rules in the main profile, eg. if there is a deny in the main profile there isn't currently a way to override that in local
    17:12 <jjohansen> twb: I don't think genprof supports writing to local yet, I know its planned for
    17:12 <jjohansen> cboltz can speak to it better than I can
    17:13 <jjohansen> twb: when apparmor 3 lands you will also have the option of setting up policy overlay directories
    17:13 <jjohansen> so you could setup, a local overlay say
    17:13 <jjohansen>  /etc/apparmor-local.d/
    17:13 <jjohansen> or what ever you want to call it
    17:14 <jjohansen> and drop a copy of the profile into that
    17:14 <jjohansen> and edit it directly
    17:14 <jjohansen> if a file is in the override dir, it will be used instead of the file underneath
    17:14 <jjohansen> sadly that isn't available to you yet
    17:15 <jjohansen> 2.13 only supports it for caches

[BIG GAP WHERE I GOT SICK OF COPY-PASTE-PRUNING ALL MY IRC LOGS ]

2019-06-25 #dovecot::

    15:59 <twb> cmouse: hey you know how you removed NoNewPrivileges because sendmail_program (may) need setgid?  [https://github.com/dovecot/core/commit/a66e59551]
    16:00 <cmouse> twb: yes?
    16:00 <twb> I have a horrific workaround
    16:00 <twb> BindReadOnlyPaths=/usr/bin/msmtp:/usr/sbin/sendmail
    16:00 <cmouse> that ... can't possibly work
    16:01 <twb> msmtp doesn't need setgid, so you just tell it to send to localhost:25, which is postfix
    16:01 <cmouse> ah.
    16:01 <twb> I'm testing it now
    16:01 <cmouse> you are right, it's horrific.
    16:01 <xrandr> cmouse: how much of the configuration would need to be changed?
    16:01 <cmouse> xrandr: impossible to say without knowing
    16:01 <cmouse> https://wiki.dovecot.org/Upgrading this might help
    16:02 <twb> (It does mean you need to allow AF_INET/6 and IPAddressAllow=localhost, but dovecot at least already needs that much)
    16:03 <cmouse> twb: why not just sent sendmail_path=/usr/bin/msmtp?
    16:03 <xrandr> cmouse: thanks, I'll look into it. For now, it is workign
    16:04 <twb> cmouse: only because that's dovecot-specific and I want to reuse this for e.g. smartd
    16:04 <twb> (and smartd just calls /bin/mail, which calls /usr/sbin/sendmail)
    16:04 <cmouse> twb: btw, i have better idea for you.
    16:04 <twb> Oh, also, because systemd will error out if /bin/msmtp isn't installed
    16:05 <cmouse> try setting 'submission_host=localhost:25' in your config
    16:05 <twb> cmouse: you mean in the postfix main.cf?
    16:05 <cmouse> no, i mean in dovecot config
    16:05 <twb> ah Ok
    16:05 <cmouse> and set sendmail_path=
    16:05 <cmouse> assuming you have 2.3.6 or so
    16:06 <cmouse> ah, no, that has been there for 2.0.10
    16:06 <cmouse> so "should work"
    16:06 <cmouse> q
    16:29 <twb> cmouse: this is working, yay!  http://ix.io/1MJb/ini
    16:29 <cmouse> can you also try the submission_host alternative?
    16:29 <twb> So I can basically use that last paragraph as a "drop in" for all the units I want to have sendmail access
    16:30 <twb> cmouse: sure.  How do I trigger dovecot to try to send an email?
    16:30 <cmouse> twb: vacation?
    16:30 <twb> Right now I don't even have dovecot set up as the LDA; it's basically a fresh debian 10 install
    16:31 <cmouse> twb: sieve vacation is one way to trigger such thing
    16:33 <twb> is there a CLI / TUI sieve client?
    16:33 <cmouse> doveadm sieve
    16:33 <twb> I guess I can just write a sieve file and drop it in by hand
    16:33 [twb RTFM's doveadm sieve]
    16:33 <cmouse> it's slightly safer way to drop it in by hand
    16:36 <twb> Hahaha.  "doveadm sieve list -A" complains about systemd-coredump account (uid=999)
    16:37 <cmouse> twb: yes.
    16:37 <cmouse> twb: there is also min_valid_uid setting
    16:40 <twb> Hrm, I'm very surprised that's not set to 1000 on Debian by default
    16:48 <twb> doveadm also "saw" the user created on-the-fly to execute ntpwait.  Even though ntpwait ends, RemainAfterExit was on, so systemd kept the "temporary" account in nss, where doveadm could see it via getpwent
    16:49 <twb> That took me a little white to debug
    17:11 <twb> OK, I've been stuck for a bit.
    17:11 <twb> root@not-omega:~# doveadm sieve put -u test1 -a vacation-test.sieve < vacation-test.sieve
    17:11 <twb> doveadm(test1): Error: Mailbox INBOX: file_dotlock_create(test1) in directory /var/mail failed: Permission denied (euid=1001(test1) egid=8(mail) missing +w perm: /var/mail, dir owned by 0:0 mode=0755)
    17:11 <twb> That's even with systemd lockdown turned off and dovecot restarted
    17:12 <twb> What dumb thing have I missed?  Maybe that sieve isn't allowed for plain mbox, only maildir/dbox?
    17:13 <twb> Hrm, /home/test1/sieve/vacation-test.sieve.sieve  exists
    17:16 <cmouse> twb: did you enable?
    17:16 <twb> enable what?
    17:16 <cmouse> the sieve script
    17:16 <twb> Isn't that what the -a (tries to) do?
    17:16 <cmouse> well, check with 'doveadm sieve list -u test1'
    17:16 <cmouse> it should tell you if it's active or not
    17:17 <cmouse> also, you need to have 'sieve' plugin loaded for lda/lmtp
    17:17 <twb> vacation-test.sieve ACTIVE
    17:17 <cmouse> twb: also, /var/mail is 0:0
    17:17 <cmouse> twb: dovecot can't create test1 in there then
    17:17 <cmouse> twb: you either need to create and chown yourself, change /var/mail privs, and optionally use mail_privileged_group
    17:18 <twb> There is already a /var/mail/test1 mbox -- http://ix.io/1MJk
    17:18 <cmouse> did you use ProtectSystem=strict?
    17:18 <twb> That's off, and in any case the error is coming from doveadm, which is running unconfined
    17:19 <cmouse> can you show 'doveadm user test1'?
    17:19 <twb> Maybe "dotlocks" need elevated privileges
    17:19 <cmouse> no,.
    17:19 <cmouse> and 'doveconf -n' too
    17:19 <twb> I notice that both mailutils and mutt have setgid binaries for their dotlocks
    17:19 <cmouse> sure.
    17:19 <cmouse> but it's not needed.
    17:20 <cmouse> dotlock = create a .file
    17:20 <twb> http://ix.io/1MJl  doveadm user test1
    17:20 <cmouse> ah.
    17:20 <twb> doveconf -n http://ix.io/1MJm
    17:21 <cmouse> do you also have /home/test1 ?
    17:21 <twb> Yep
    17:21 <cmouse> k
    17:21 <twb> http://ix.io/1MJp
    17:21 <cmouse> btw, you probably want to use %Lu instead of %u
    17:21 <cmouse> aaaaaa... heh =)
    17:21 <twb> That's just whatever Debian gave me; I haven't messed with the dovecot config at all yet.
    17:22 <cmouse> try setting mail_location = mbox:~/mail:INBOX=/var/mail/%u:INDEX=~/mail/.index/
    17:22 <cmouse> or something like that
    17:22 <twb> Will it be simpler to just switch to maildir or dbox?  Because that's part of the end goal anyway
    17:22 <cmouse> also, for the record, i don't think you should use mbox at all
    17:22 <cmouse> i'd use maildir at least.
    17:25 <twb> Is "mail_location = mdbox:/var/mail/%Lu" good enough, or do I need to set an INDEX separately
    17:26 <cmouse> uhm.. why do you think that would work?
    17:26 <cmouse> you probably don't want to use /var/mail for mdbox.
    17:26 <twb> OK.  I definitely want mail and $HOME to be on separate filesystems, at least.
    17:27 <cmouse> k
    17:27 <cmouse> you can use /var/mail
    17:27 <cmouse> but mdbox is going to be a *directory* not a *file*
    17:27 <twb> understood
    17:28 <twb> It's a test server; I'm just moving the old mboxes away and not caring
    17:28 <cmouse> ok
    17:30 <twb> Yeah OK so mail_location alone still needs $HOME access for some stuff; I guess to "protect" dovecot internals from direct user meddling I want to set mail_home as well, like you suggested yesterday
    17:30 <twb> (My other concern there would be EDQUOT, because I have strict quotas on $HOME, but not on mail)
    17:45 <cmouse> btw, you should probably read up on how mdbox works
    17:45 <cmouse> because it needs regular maintenance to work properly.
    17:45 <twb> oh well in that case I'll just continue using maildir and not giving a shit :-)
    17:47 <twb> With "mail_location = maildir:/var/mail/%Lu", doveadm no longer gives me any errors.
    17:47 <cmouse> uh, maildir expects a directory as wel.
    17:47 <cmouse> as well
    17:48 <twb> Yeah I know.
    17:48 <cmouse> you could've tried making /var/mail/.imap folder, chmod 1777
    17:48 <cmouse> just came to mind
    17:49 <twb> Hum, OK
    17:49 <twb> Anyway, after all that, I now have a vacation sieve script installed and active.  Now, how do I get it to fire the sieve script?
    17:49 <cmouse> just deliver mail to user.
    17:50 <cmouse> you can directly execute dovecot-lda
    17:50 <twb> Ah but remember 16:30 <twb> Right now I don't even have dovecot set up as the LDA; it's basically a fresh debian 10 install
    17:50 <twb> Oh OK
    17:50 <cmouse> dovecot-lda -f some@fake.address -d test1 -a test1@fake.address
    17:50 <cmouse> then just write some crap and press ctrl+d
    17:50 <cmouse> on it's own line.
    17:59 <twb> OK, dovecot-lda is delivering the message, but not a vacation message back (I think), probably because my sieve script is broken  http://ix.io/1MJx  http://ix.io/1MJw
    17:59 <twb> I'll try running sievec on it
    17:59 <twb> no errors or output from sievec
    18:00 <twb> I can see /home/test1/.dovecot.sieve but I can't see a compiled version, like I remember from last time I did sieve stuff
    18:03 <cmouse> twb: it's compiled lazily.
    18:03 <twb> Righto

2019-06-25 #postfix::

    15:27 <twb> OK, I have a stupid idea, and I want you to listen to the backstory and then tell me HOW stupid it is.
    15:28 <twb> 1. systemd has a bunch of "drop privileges" features for daemons. e.g. seccomp bpf to make anything that tries to call mount(2) do a core dump instead
    15:29 <twb> 2. a bunch of those implicitly break setgid binaries.  Which is rarely an issue, EXCEPT THAT postdrop is sgid postfix, and lots of things want to use /usr/sbin/sendmail (which uses postdrop).
    15:31 <twb> 3. so screw it, just make /usr/sbin/sendmail be msmtp instead, using localhost as the smarthost, and postfix set to be allow relay for localhost clients.
    15:32 <twb> That way I only need to allow loopback network access, not all the things that would otherwise break postdrop sgid.
    15:32 <twb> The immediate example I have right now is dovecot --- https://github.com/dovecot/core/commit/a66e595515ab579a875a2e9b8116be5da45fb5d6#diff-5bbec0a0006d92d441b5c8fa72690f95
    15:33 <twb> But my other test case is smartd (which sends an email when your disk is dying).
    15:33 <twb> So, how crazy is this plan?
    16:31 <twb> I tested it and it's working, yay! http://ix.io/1MJb/ini

    18:15 <pj> twb: there are a number of good reasons to replace the sendmail binary with msmtp, but I have never had problems with systemd and the postfix sendmail binary, it has always just worked for me.  I would say something is wrong with your install if it doesn't.
    18:16 <twb> pj: I've told systemd to block setgid
    18:17 <pj> oh, in that case the ramifications are on you.
    18:17 <twb> Yeah understood :-)
    18:18 <twb> It's in the same general bucket as "I blocked bad things with SELinux/Apparmor, and now a good thing is also blocked"
    18:18 <pj> there is nothing wrong with wanting a more secure system, but do realize the most secure system is one that can't do anything at all.  I would see if you can put an exception in for postdrop.
    18:18 <blackflow> twb: in my book, if I block something with selinux/apparmor that I think should be blocked and a piece of software breaks, I'd drop that software if possible. No excuse for bad practices.
    18:18 <pj> ...or just use msmtp like you're doing, there are other advantages to that, actually.
    18:18 <twb> pj: I can punch a hole for postdrop sgid, but it's a much bigger hole
    18:19 <pj> you get all the smtp_* features with msmtp, which you don't get with pickup.
    18:20 <pj> blackflow: it's really not a bad practice just because postfix uses a feature of the filesystem that someone arbitrarily decides to block for their own security reasons.  It's not even a security feature that is enabled by default in any distro that I know of.
    18:22 <twb> Actually for daemons that run as root, the whitelist difference isn't too big --- http://ix.io/1MJz/ini (postdrop)  versus  http://ix.io/1MJA/ini (msmtp)
    18:23 <twb> it's bigger for daemons that have all their privileges taken away before systemd even starts them
    18:24 <twb> BTW if you're curious, this command will print all the things that are suid/sgid/sticky: find -O3 / -xdev -type f -executable -perm /6000 -ls
    18:24 <blackflow> running daemons as non-root (with some cap_net_bind_service magick) is what I'd prefer where possible too. I haven't yet sat down to talk with postfix about that tho :)
    18:24 <twb> Mostly they're su/sudo/pkexec and chfn/chpw things
    18:25 <twb> blackflow: mariadb does that by default now, to my great surprise
    18:26 <blackflow> you mean the maintainer of mariadb for your distro configured the service unit to do so? important distinction. something I'd like to see done more in Debian but it won't be as they still wanna support sysv
    18:26 <twb> blackflow: no, I mean upstream
    18:26 <twb> https://mariadb.com/kb/en/library/systemd/
    18:26 <blackflow> twb: in the daemon itself?
    18:26 <blackflow> oh you mean upstream packaged service unit?
    18:27 <twb> blackflow: yes
    18:27 <blackflow> yes, but distros will change that.
    18:29 <twb> blackflow: if you're curious, http://cyber.com.au/~twb/tmp/systemd_241_lockdown.txz  (work in progress)
    18:30 <blackflow> what's that?
    18:30 <twb> That's the "block all the things!" rules I'm dropping on top of various services
    18:31 <twb> (See also "systemd-analyze security")
    18:32 <blackflow> ah, run unpriv, with caps where needed, readonly fs view, strict, rw where minimally needed, private tmp, no access to dev, seccomp lockdown, ... ?
    18:33 <twb> blackflow: yep all that stuff
    18:34 <blackflow> that's what I'm doing where possible, but haven't yet gotten to setup postfix like that.
    18:34 <twb> blackflow: I'd be curious to see your results; I can be found on #emacs most weekdays

2019-07-10 #systemd::

    15:46 <twb> does the dbus unit actually "do things", or does it just send and receive IPC calls?
    15:46 <twb> I assume whenever dbus wants to e.g. start up polkitd to ask it a question, that's actually implemented by sending an IPC to systemd saying "btw please start polkit" --- dbus itself doesn't actually need and privileges at all
    15:47 <grawity> dbus-daemon traditionally execs daemons on its own (through a setuid helper)
    15:47 <twb> I thought it stopped doing that when systemd landed
    15:48 <grawity> nowadays 99% of system bus services are systemd-activatable, as in their D-Bus .service files refer to a SystemdService= (and some don't even have a valid Exec= anymore)
    15:48 <twb> I remember seeing messages along the lines of "activated (via systemd)"
    15:48 <twb> grawity: ah so it's basically opt-in on a per dbus listener basis, and in practice most of them do, but in theory one might not?
    15:48 <grawity> yes
    15:48 <twb> ohhh
    15:48 <twb> I thought it was automatically done via a generator that read all the dbus listener xml files
    15:50 <grawity> (of course, all of that only applies when a client tries to contact a service that isn't running yet – if it's already running and claimed the bus name, then there's no further "activation" needed)
