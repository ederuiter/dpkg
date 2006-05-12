#!/usr/bin/perl
#
# Options:
#  -v<version>
#   changes since <version>

$dpkglibdir= ".";
$version= '1.3.0'; # This line modified by Makefile

$controlfile= 'debian/control';
$changelogfile= 'debian/changelog';
$fileslistfile= 'debian/files';
$varlistfile= 'debian/substvars';

push(@INC,$dpkglibdir);
require 'controllib.pl';

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

$progname= "parsechangelog/$progname";

$since='';

sub usageversion {
    print STDERR _g(
"Debian %s %s.  Copyright (C) 1996
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage: %s [-v<versionsince>] | -h
"), $progname, $version, $progname;
}

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-v(.+)$/) {
        $since= $1;
    } elsif (m/^-h$/) {
        &usageversion; exit(0);
    } else {
        &usageerr(sprintf(_g("unknown option or argument \`%s'"), $_));
    }
}

%mapkv=(); # for future use
$i=100;grep($fieldimps{$_}=$i--,
          qw(Source Version Distribution Urgency Maintainer Date Closes
	     Changes));
$i=1;grep($urgencies{$_}=$i++,
          qw(low medium high critical emergency));

$expect='first heading';

while (<STDIN>) {
    s/\s*\n$//;
#    printf(STDERR "%-39.39s %-39.39s\n",$expect,$_);
    if (m/^(\w[-+0-9a-z.]*) \(([^\(\) \t]+)\)((\s+[-+0-9a-z.]+)+)\;/i) {
        if ($expect eq 'first heading') {
            $f{'Source'}= $1;
            $f{'Version'}= $2;
            $f{'Distribution'}= $3;
            &error(_g("-v<since> option specifies most recent version")) if
                $2 eq $since;
            $f{'Distribution'} =~ s/^\s+//;
        } elsif ($expect eq 'next heading or eof') {
            last if $2 eq $since;
            $f{'Changes'}.= " .\n";
        } else {
            &clerror(sprintf(_g("found start of entry where expected %s"), $expect));
        }
        $rhs= $'; $rhs =~ s/^\s+//;
        undef %kvdone;
        for $kv (split(/\s*,\s*/,$rhs)) {
            $kv =~ m/^([-0-9a-z]+)\=\s*(.*\S)$/i ||
                &clerror(sprintf(_g("bad key-value after \`;': \`%s'"), $kv));
            $k=(uc substr($1,0,1)).(lc substr($1,1)); $v=$2;
            $kvdone{$k}++ && &clwarn(sprintf(_g("repeated key-value %s"), $k));
            if ($k eq 'Urgency') {
                $v =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
                    &clerror(_g("badly formatted urgency value, at changelog "));
                $newurg= lc $1;
                $newurgn= $urgencies{lc $1}; $newcomment= $2;
                $newurgn ||
                    &clwarn(sprintf(_g("unknown urgency value %s - comparing very low"), $newurg));
                if (defined($f{'Urgency'})) {
                    $f{'Urgency'} =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
                        &internerr(sprintf(_g("urgency >%s<"), $f{'Urgency'}));
                    $oldurg= lc $1;
                    $oldurgn= $urgencies{lc $1}; $oldcomment= $2;
                } else {
                    $oldurgn= -1;
                    $oldcomment= '';
                }
                $f{'Urgency'}=
                    (($newurgn > $oldurgn ? $newurg : $oldurg).
                     $oldcomment.
                     $newcomment);
            } elsif (defined($mapkv{$k})) {
                $f{$mapkv{$k}}= $v;
            } elsif ($k =~ m/^X[BCS]+-/i) {
                # Extensions - XB for putting in Binary,
                # XC for putting in Control, XS for putting in Source
                $f{$k}= $v;
            } else {
                &clwarn(sprintf(_g("unknown key-value key %s - copying to %s"), $k, "XS-$k"));
                $f{"XS-$k"}= $v;
            }
        }
        $expect= 'start of change data'; $blanklines=0;
        $f{'Changes'}.= " $_\n .\n";
    } elsif (m/^\S/) {
        &clerror(_g("badly formatted heading line"));
    } elsif (m/^ \-\- (.*) <(.*)>  ((\w+\,\s*)?\d{1,2}\s+\w+\s+\d{4}\s+\d{1,2}:\d\d:\d\d\s+[-+]\d{4}(\s+\([^\\\(\)]\))?)$/) {
        $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found trailer where expected %s"), $expect));
        $f{'Maintainer'}= "$1 <$2>" unless defined($f{'Maintainer'});
        $f{'Date'}= $3 unless defined($f{'Date'});
#        $f{'Changes'}.= " .\n $_\n";
        $expect= 'next heading or eof';
        last if $since eq '';
    } elsif (m/^ \-\-/) {
        &clerror(_g("badly formatted trailer line"));
    } elsif (m/^\s{2,}\S/) {
        $expect eq 'start of change data' || $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found change data where expected %s"), $expect));
        $f{'Changes'}.= (" .\n"x$blanklines)." $_\n"; $blanklines=0;
        $expect= 'more change data or trailer';
    } elsif (!m/\S/) {
        next if $expect eq 'start of change data' || $expect eq 'next heading or eof';
        $expect eq 'more change data or trailer' ||
            &clerror(sprintf(_g("found blank line where expected %s"), $expect));
        $blanklines++;
    } else {
        &clerror(_g("unrecognised line"));
    }
}

$expect eq 'next heading or eof' || die sprintf(_g("found eof where expected %s"), $expect);

$f{'Changes'} =~ s/\n$//;
$f{'Changes'} =~ s/^/\n/;

while ($f{'Changes'} =~ /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/ig) {
  push(@closes, $& =~ /\#?\s?(\d+)/g);
}
$f{'Closes'} = join(' ',sort { $a <=> $b} @closes);

&outputclose(0);

sub clerror { &error(sprintf(_g("%s, at changelog line %d"), $_[0], $.)); }
sub clwarn { &warn(sprintf(_g("%s, at changelog line %d"), $_[0], $.)); }
