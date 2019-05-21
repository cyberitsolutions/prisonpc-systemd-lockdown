#!/usr/bin/python3

# GOAL: we want to apply "systemd-analyze security" lockdown to all units.
#       We should focus on the most-used units first.
#       So print a list of units, ordered by decreasing popularity.
#
# This combines data in the Packages.xz (apt-file) database and the by-inst (popcon) databases.

import gzip
import os
import sqlite3
import subprocess

# These two commands are slow, so they're persistent between runs.
subprocess.check_call('wget -nc https://popcon.debian.org/by_inst.gz'.split())
if not os.path.exists('apt-file.stdout'):
    with open('apt-file.stdout', 'w') as f:
        subprocess.check_call(
            ['apt-file', 'search', '--regexp', 'systemd/system/[^/]*\.service$'],
            stdout=f)

# This step is relatively fast, so we don't persist it between runs.
with sqlite3.connect(':memory:') as conn:
    #conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA wal_mode = journal')
    ## One or more units aren't known to popcon, but I can't be arsed finding out which it is.
    ## UPDATE: by doing a "LEFT JOIN" instead of a "JOIN", they'll show up with a rank of "None" (NULL).
    #conn.execute('PRAGMA foreign_keys = 1')
    conn.execute('CREATE TABLE popcon (package TEXT PRIMARY KEY, rank INTEGER NOT NULL)')
    conn.execute('CREATE TABLE units (package TEXT NOT NULL REFERENCES popcon, unit_path TEXT NOT NULL)')

    with gzip.open('by_inst.gz', 'rt') as f:
        conn.executemany(
            'INSERT INTO popcon VALUES (?, ?)',
            ((words[1], words[0])
             for line in f
             for words in [line.split()]
             if words[0].isdigit()))

    with open('apt-file.stdout') as f:
        conn.executemany(
            'INSERT INTO units VALUES (?, ?)',
            (((package, unit_path)
              for line in f
              for package, _, unit_path in [line.strip().partition(': ')])))

    for row in conn.execute('SELECT rank, package, unit_path FROM units NATURAL LEFT JOIN popcon ORDER BY 1, 2, 3'):
        print(*row, sep='\t')
