#! /usr/bin/perl
#
# dpkg-architecture
#
# Copyright © 2004-2005 Scott James Remnant <scott@netsplit.com>,
# Copyright © 1999 Marcus Brinkmann <brinkmd@debian.org>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning syserr usageerr);
use Dpkg::Arch qw(get_valid_arches debarch_eq debarch_is
                  debtriplet_to_gnutriplet gnutriplet_to_debtriplet
                  debtriplet_to_debarch debarch_to_debtriplet);

textdomain("dpkg-dev");

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1999-2001 Marcus Brinkmann <brinkmd\@debian.org>.
Copyright (C) 2004-2005 Scott James Remnant <scott\@netsplit.com>.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] [<action>]

Options:
  -a<debian-arch>    set current Debian architecture.
  -t<gnu-system>     set current GNU system type.
  -L                 list valid architectures.
  -f                 force flag (override variables set in environment).

Actions:
  -l                 list variables (default).
  -e<debian-arch>    compare with current Debian architecture.
  -i<arch-alias>     check if current Debian architecture is <arch-alias>.
  -q<variable>       prints only the value of <variable>.
  -s                 print command to set environment variables.
  -u                 print command to unset environment variables.
  -c <command>       set environment and run the command in it.
  --help             show this help message.
  --version          show the version.
"), $progname;
}

sub list_arches()
{
    foreach my $arch (get_valid_arches()) {
	print "$arch\n";
    }
}


my $req_host_arch = '';
my $req_host_gnu_type = '';
my $req_build_gnu_type = '';
my $req_eq_arch = '';
my $req_is_arch = '';
my $req_variable_to_print;
my $action = 'l';
my $force = 0;

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-a/) {
	$req_host_arch = "$'";
    } elsif (m/^-t/) {
	$req_host_gnu_type = "$'";
    } elsif (m/^-e/) {
	$req_eq_arch = "$'";
	$action = 'e';
    } elsif (m/^-i/) {
	$req_is_arch = "$'";
	$action = 'i';
    } elsif (m/^-[lsu]$/) {
	$action = $_;
	$action =~ s/^-//;
    } elsif (m/^-f$/) {
        $force=1;
    } elsif (m/^-q/) {
        $req_variable_to_print = "$'";
        $action = 'q';
    } elsif (m/^-c$/) {
       $action = 'c';
       last;
    } elsif (m/^-L$/) {
        list_arches();
        exit unless @ARGV;
    } elsif (m/^-(h|-help)$/) {
       &usage;
       exit 0;
    } elsif (m/^--version$/) {
       &version;
       exit 0;
    } else {
	usageerr(_g("unknown option \`%s'"), $_);
    }
}

# Set default values:

chomp (my $deb_build_arch = `dpkg --print-architecture`);
&syserr("dpkg --print-architecture failed") if $?>>8;
my $deb_build_gnu_type = debtriplet_to_gnutriplet(debarch_to_debtriplet($deb_build_arch));

# Default host: Current gcc.
my $gcc = `\${CC:-gcc} -dumpmachine`;
if ($?>>8) {
    warning(_g("Couldn't determine gcc system type, falling back to default (native compilation)"));
    $gcc = '';
} else {
    chomp $gcc;
}

my $deb_host_arch = undef;
my $deb_host_gnu_type;

if ($gcc ne '') {
    my (@deb_host_archtriplet) = gnutriplet_to_debtriplet($gcc);
    $deb_host_arch = debtriplet_to_debarch(@deb_host_archtriplet);
    unless (defined $deb_host_arch) {
	warning(_g("Unknown gcc system type %s, falling back to default " .
	           "(native compilation)"), $gcc);
	$gcc = '';
    } else {
	$gcc = $deb_host_gnu_type = debtriplet_to_gnutriplet(@deb_host_archtriplet);
    }
}
if (!defined($deb_host_arch)) {
    # Default host: Native compilation.
    $deb_host_arch = $deb_build_arch;
    $deb_host_gnu_type = $deb_build_gnu_type;
}

if ($req_host_arch ne '' && $req_host_gnu_type eq '') {
    $req_host_gnu_type = debtriplet_to_gnutriplet(debarch_to_debtriplet($req_host_arch));
    die (sprintf(_g("unknown Debian architecture %s, you must specify GNU system type, too"), $req_host_arch)) unless defined $req_host_gnu_type;
}

if ($req_host_gnu_type ne '' && $req_host_arch eq '') {
    $req_host_arch = debtriplet_to_debarch(gnutriplet_to_debtriplet($req_host_gnu_type));
    die (sprintf(_g("unknown GNU system type %s, you must specify Debian architecture, too"), $req_host_gnu_type)) unless defined $req_host_arch;
}

if ($req_host_gnu_type ne '' && $req_host_arch ne '') {
    my $dfl_host_gnu_type = debtriplet_to_gnutriplet(debarch_to_debtriplet($req_host_arch));
    die (sprintf(_g("unknown default GNU system type for Debian architecture %s"),
                 $req_host_arch))
	unless defined $dfl_host_gnu_type;
    warning(_g("Default GNU system type %s for Debian arch %s does not " .
               "match specified GNU system type %s"), $dfl_host_gnu_type,
            $req_host_arch, $req_host_gnu_type)
        if $dfl_host_gnu_type ne $req_host_gnu_type;
}

$deb_host_arch = $req_host_arch if $req_host_arch ne '';
$deb_host_gnu_type = $req_host_gnu_type if $req_host_gnu_type ne '';

#$gcc = `\${CC:-gcc} --print-libgcc-file-name`;
#$gcc =~ s!^.*gcc-lib/(.*)/\d+(?:.\d+)*/libgcc.*$!$1!s;
warning(_g("Specified GNU system type %s does not match gcc system type %s."),
        $deb_host_gnu_type, $gcc)
    if !($req_is_arch or $req_eq_arch) &&
       ($gcc ne '') && ($gcc ne $deb_host_gnu_type);

# Split the Debian and GNU names
my ($deb_host_arch_abi, $deb_host_arch_os, $deb_host_arch_cpu) = debarch_to_debtriplet($deb_host_arch);
my ($deb_build_arch_abi, $deb_build_arch_os, $deb_build_arch_cpu) = debarch_to_debtriplet($deb_build_arch);
my ($deb_host_gnu_cpu, $deb_host_gnu_system) = split(/-/, $deb_host_gnu_type, 2);
my ($deb_build_gnu_cpu, $deb_build_gnu_system) = split(/-/, $deb_build_gnu_type, 2);

my %env = ();
if (!$force) {
    $deb_build_arch = $ENV{DEB_BUILD_ARCH} if (exists $ENV{DEB_BUILD_ARCH});
    $deb_build_arch_os = $ENV{DEB_BUILD_ARCH_OS} if (exists $ENV{DEB_BUILD_ARCH_OS});
    $deb_build_arch_cpu = $ENV{DEB_BUILD_ARCH_CPU} if (exists $ENV{DEB_BUILD_ARCH_CPU});
    $deb_build_gnu_cpu = $ENV{DEB_BUILD_GNU_CPU} if (exists $ENV{DEB_BUILD_GNU_CPU});
    $deb_build_gnu_system = $ENV{DEB_BUILD_GNU_SYSTEM} if (exists $ENV{DEB_BUILD_GNU_SYSTEM});
    $deb_build_gnu_type = $ENV{DEB_BUILD_GNU_TYPE} if (exists $ENV{DEB_BUILD_GNU_TYPE});
    $deb_host_arch = $ENV{DEB_HOST_ARCH} if (exists $ENV{DEB_HOST_ARCH});
    $deb_host_arch_os = $ENV{DEB_HOST_ARCH_OS} if (exists $ENV{DEB_HOST_ARCH_OS});
    $deb_host_arch_cpu = $ENV{DEB_HOST_ARCH_CPU} if (exists $ENV{DEB_HOST_ARCH_CPU});
    $deb_host_gnu_cpu = $ENV{DEB_HOST_GNU_CPU} if (exists $ENV{DEB_HOST_GNU_CPU});
    $deb_host_gnu_system = $ENV{DEB_HOST_GNU_SYSTEM} if (exists $ENV{DEB_HOST_GNU_SYSTEM});
    $deb_host_gnu_type = $ENV{DEB_HOST_GNU_TYPE} if (exists $ENV{DEB_HOST_GNU_TYPE});
}

my @ordered = qw(DEB_BUILD_ARCH DEB_BUILD_ARCH_OS DEB_BUILD_ARCH_CPU
                 DEB_BUILD_GNU_CPU DEB_BUILD_GNU_SYSTEM DEB_BUILD_GNU_TYPE
                 DEB_HOST_ARCH DEB_HOST_ARCH_OS DEB_HOST_ARCH_CPU
                 DEB_HOST_GNU_CPU DEB_HOST_GNU_SYSTEM DEB_HOST_GNU_TYPE);

$env{'DEB_BUILD_ARCH'}=$deb_build_arch;
$env{'DEB_BUILD_ARCH_OS'}=$deb_build_arch_os;
$env{'DEB_BUILD_ARCH_CPU'}=$deb_build_arch_cpu;
$env{'DEB_BUILD_GNU_CPU'}=$deb_build_gnu_cpu;
$env{'DEB_BUILD_GNU_SYSTEM'}=$deb_build_gnu_system;
$env{'DEB_BUILD_GNU_TYPE'}=$deb_build_gnu_type;
$env{'DEB_HOST_ARCH'}=$deb_host_arch;
$env{'DEB_HOST_ARCH_OS'}=$deb_host_arch_os;
$env{'DEB_HOST_ARCH_CPU'}=$deb_host_arch_cpu;
$env{'DEB_HOST_GNU_CPU'}=$deb_host_gnu_cpu;
$env{'DEB_HOST_GNU_SYSTEM'}=$deb_host_gnu_system;
$env{'DEB_HOST_GNU_TYPE'}=$deb_host_gnu_type;

if ($action eq 'l') {
    foreach my $k (@ordered) {
	print "$k=$env{$k}\n";
    }
} elsif ($action eq 's') {
    foreach my $k (@ordered) {
	print "$k=$env{$k}; ";
    }
    print "export ".join(" ",@ordered)."\n";
} elsif ($action eq 'u') {
    print "unset ".join(" ",@ordered)."\n";
} elsif ($action eq 'e') {
    exit !debarch_eq($deb_host_arch, $req_eq_arch);
} elsif ($action eq 'i') {
    exit !debarch_is($deb_host_arch, $req_is_arch);
} elsif ($action eq 'c') {
    @ENV{keys %env} = values %env;
    exec @ARGV;
} elsif ($action eq 'q') {
    if (exists $env{$req_variable_to_print}) {
        print "$env{$req_variable_to_print}\n";
    } else {
        die sprintf(_g("%s is not a supported variable name"), $req_variable_to_print);
    }
}
