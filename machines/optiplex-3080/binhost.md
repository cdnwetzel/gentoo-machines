# OptiPlex 3080 — T5810 binhost (install day + steady state)

The full @world set is prebuilt on precision-t5810 as binpkgs:
`/opt/buildhosts/optiplex-3080/var/cache/binpkgs/` (gpkg format, with Packages index).

Topology: the 3080 (198.51.100.x) CANNOT route to T5810 (192.0.2.125) directly,
but CAN reach `jump.example.net` on TCP/22. So the binhost is served on the T5810
loopback and reached through an SSH tunnel. user can read the binpkgs dir —
no root needed to serve.

## Install day (inside the Gentoo chroot on the 3080)

On T5810 (or leave running):

    ssh chris@jump.example.net
    cd /opt/buildhosts/optiplex-3080/var/cache/binpkgs
    python3 -m http.server 8787 --bind 127.0.0.1

On the 3080 live session, before part3's @world emerge:

    ssh -N -L 8787:127.0.0.1:8787 chris@jump.example.net &   # stays up during install
    # in the chroot:
    printf 'PORTAGE_BINHOST="http://127.0.0.1:8787/"\nFEATURES="${FEATURES} getbinpkg"\n' \
        >> /etc/portage/make.conf
    emerge --getbinpkg --usepkg --update --deep --newuse @world

If a binpkg is missing/stale, emerge falls back to a local source build —
slower, not broken. The prebuilt kernel (prebuilt/kernel-artifacts.tar.gz)
is installed separately; see INSTALL_PREFLIGHT.md.

## Steady state (updates)

Same tunnel pattern from the installed system; or if the 3080 ever lands on
the 192.0.2.0/24 network, point PORTAGE_BINHOST at a permanent server on the
T5810 instead. Rebuild binpkgs on T5810 with:

    sudo chroot /opt/buildhosts/optiplex-3080 /bin/bash -lc \
        'emerge --sync && emerge -uDN --keep-going @world'

then on the 3080: `emerge --getbinpkg --usepkg -uDN @world`.
Do NOT update the 3080's portage tree ahead of the binhost — binpkgs are
valid against the tree they were built from; sync the 3080 from the chroot's
snapshot (`/opt/buildhosts/optiplex-3080/var/db/repos/gentoo`) if you want
lockstep.

## Rules that keep this safe

- The chroot's make.conf is the BUILD variant (-j40); the machine's make.conf
  on the 3080 is the honest local-fallback variant (-j4 -l6). They must agree
  on: COMMON_FLAGS, USE, CPU_FLAGS_X86, PYTHON_*, ACCEPT_KEYWORDS.
  `machines/optiplex-3080/make.conf` is the source of truth for both.
- Never edit the chroot's package.use/package.accept_keywords directly —
  edit the repo files and push, so install media rebuilds stay reproducible.
