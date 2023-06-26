#!/usr/bin/python3
import csv
import gzip
import pprint
import re
import sqlite3
import subprocess

__doc__ = """ list all packages that have an /etc/init.d/X but and corresponding /lib/systemd/system/X.service, ordered by descending popularity """


# FIXME: this is bloody slow - I should use "import apt_pkg" or something.
def binary_package_to_source_package(binary_package: str) -> str:
    source_package = subprocess.check_output(
        ['grep-aptavail', '-sSource', '--no-field-name', '--exact-match', '-P', binary_package],
        text=True).strip()
    if source_package:
        # change "android-androresolvd (1.3-1)" to "android-androresolvd"
        return source_package.split()[0]
    else:
        # no match, so source_package = binary_package
        return binary_package


n=0                             # PROGRESS DEBUGGING
with sqlite3.connect(':memory:') as conn:
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    conn.execute('CREATE TEMPORARY TABLE data (popularity INTEGER, source_package, binary_package, script, already_done DEFAULT 0)')
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    conn.executemany(
        'INSERT INTO data (binary_package, script) VALUES (?, ?)',
        re.findall(r'(.*): /etc/init.d/(.*)\n',
                   subprocess.check_output(
                       'apt-file search /etc/init.d/'.split(),
                       text=True)))
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    conn.executemany(
        'UPDATE data SET already_done = 1 WHERE binary_package = ? AND script = ?',
        re.findall(r'(.*): /lib/systemd/system/(.*)\.service\n',
                   subprocess.check_output(
                       'apt-file search /lib/systemd/system/'.split(),
                       text=True)))
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    conn.executemany(
        'UPDATE data SET source_package = ? WHERE binary_package = ?',
        ((binary_package_to_source_package(binary_package), binary_package)
         for binary_package, in conn.execute('SELECT DISTINCT binary_package FROM data -- WHERE NOT already_done')))
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    subprocess.check_call('wget2 -N https://popcon.debian.org/by_inst.gz'.split())
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    with gzip.open('by_inst.gz', 'rt', encoding='ISO-8859-1') as f:
        conn.executemany(
            'UPDATE data SET popularity = ? WHERE source_package = ?',
            ((words[0], words[1])
             for line in f
             for words in [line.split()]
             if words[0].isdigit()))
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
    def fuck_off(x, y):
        "Just enough to convice csv.DictWriter to accept the sqlite3.Row object"
        return dict(sqlite3.Row(x, y))
    conn.row_factory = fuck_off
    with open('pre-koolaid-packages.csv', mode='w') as f:
        writer = csv.DictWriter(f, fieldnames=(
            'popularity',
            'source_package',
            'binary_package',
            'script',
            'already_done'))
        writer.writeheader()
        writer.writerows(
            conn.execute('SELECT * FROM data ORDER BY already_done, popularity, script'))
    print(n := n + 1, flush=True)  # PROGRESS DEBUGGING
