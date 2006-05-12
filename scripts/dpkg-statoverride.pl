#! /usr/bin/perl

use POSIX;
use POSIX qw(:errno_h :signal_h);

$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$version= '1.3.0'; # This line modified by Makefile

my $dpkglibdir= "."; # This line modified by Makefile
push (@INC, $dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg");

$verbose= 1;
$doforce= 0;
$doupdate= 0;
$mode= "";

sub UsageVersion {
	printf(STDERR _g(<<EOF), $version) || &quit(sprintf(_g("failed to write usage: %s"), $!));
Debian dpkg-statoverride %s.
Copyright (C) 2000 Wichert Akkerman.

This is free software; see the GNU General Public Licence version 2 or later
for copying conditions.  There is NO warranty.

Usage:

  dpkg-statoverride [options] --add <owner> <group> <mode> <file>
  dpkg-statoverride [options] --remove <file>
  dpkg-statoverride [options] --list [<glob-pattern>]

Options:
  --update                 immediately update file permissions
  --force                  force an action even if a sanity check fails
  --quiet                  quiet operation, minimal output
  --help                   print this help screen and exit
  --admindir <directory>   set the directory with the statoverride file
EOF
}

sub CheckModeConflict {
	return unless $mode;
	&badusage("two modes specified: $_ and --$mode");
}

while (@ARGV) {
	$_=shift(@ARGV);
	last if m/^--$/;
	if (!m/^-/) {
		unshift(@ARGV,$_); last;
	} elsif (m/^--help$/) {
		&UsageVersion; exit(0);
	} elsif (m/^--update$/) {
		$doupdate=1;
	} elsif (m/^--quiet$/) {
		$verbose=0;
	} elsif (m/^--force$/) {
		$doforce=1;
	} elsif (m/^--admindir$/) {
		@ARGV || &badusage(_g("--admindir needs a directory argument"));
		$admindir= shift(@ARGV);
	} elsif (m/^--add$/) {
		&CheckModeConflict;
		$mode= 'add';
	} elsif (m/^--remove$/) {
		&CheckModeConflict;
		$mode= 'remove';
	} elsif (m/^--list$/) {
		&CheckModeConflict;
		$mode= 'list';
	} else {
		&badusage(sprintf(_g("unknown option \`%s'"), $_));
	}
}

$dowrite=0;
$exitcode=0;

&badusage(_g("no mode specified")) unless $mode;
&ReadOverrides;

if ($mode eq "add") {
	@ARGV==4 || &badusage(_g("--add needs four arguments"));

	$user=$ARGV[0];
	if ($user =~ m/^#([0-9]+)$/) {
	    $uid=$1;
	    &badusage(sprintf(_g("illegal user %s"), $user)) if ($uid<0);
	} else {
	    (($name,$pw,$uid)=getpwnam($user)) || &badusage(sprintf(_g("non-existing user %s"), $user));
	}

	$group=$ARGV[1];
	if ($group =~ m/^#([0-9]+)$/) {
	    $gid=$1;
	    &badusage(sprintf(_g("illegal group %s"), $group)) if ($gid<0);
	} else {
	    (($name,$pw,$gid)=getgrnam($group)) || &badusage(sprintf(_g("non-existing group %s"), $group));
	}

	$mode= $ARGV[2];
	(($mode<0) or (oct($mode)>07777) or ($mode !~ m/\d+/)) && &badusage(sprintf(_g("illegal mode %s"), $mode));
	$file= $ARGV[3];
	$file =~ m/\n/ && &badusage(_g("file may not contain newlines"));
	$file =~ s,/+$,, && print STDERR _g("stripping trailing /")."\n";

	if (defined $owner{$file}) {
		printf STDERR _g("An override for \"%s\" already exists, "), $file;
		if ($doforce) {
			print STDERR _g("but --force specified so lets ignore it.")."\n";
		} else {
			print STDERR _g("aborting")."\n";
			exit(3);
		}
	}
	$owner{$file}=$user;
	$group{$file}=$group;
	$mode{$file}=$mode;
	$dowrite=1;

	if ($doupdate) {
	    if (not -e $file) {
		printf STDERR _g("warning: --update given but %s does not exist")."\n", $file;
	    } else {
		chown ($uid,$gid,$file) || warn sprintf(_g("failed to chown %s: %s"), $file, $!)."\n";
		chmod (oct($mode),$file) || warn sprintf(_g("failed to chmod %s: %s"), $file, $!)."\n";
	    }
	}
} elsif ($mode eq "remove") {
	@ARGV==1 || &badusage(_g("--remove needs one arguments"));
	$file=$ARGV[0];
	$file =~ s,/+$,, && print STDERR _g("stripping trailing /")."\n";
	if (not defined $owner{$file}) {
		print STDERR _g("No override present.")."\n";
		exit(0) if ($doforce); 
		exit(2);
	}
	delete $owner{$file};
	delete $group{$file};
	delete $mode{$file};
	$dowrite=1;
	print(STDERR _g("warning: --update is useless for --remove")."\n") if ($doupdate);
} elsif ($mode eq "list") {
	my (@list,@ilist,$pattern,$file);
	
	@ilist= @ARGV ? @ARGV : ('*');
	while (defined($_=shift(@ilist))) {
		s/\W/\\$&/g;
		s/\\\?/./g;
		s/\\\*/.*/g;
		s,/+$,, && print STDERR _g("stripping trailing /")."\n";
		push(@list,"^$_\$");
	}
	$pat= join('|',@list);
	$exitcode=1;
	for $file (keys %owner) {
		next unless ($file =~ m/$pat/o);
		$exitcode=0;
		print "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
}

&WriteOverrides if ($dowrite);

exit($exitcode);

sub ReadOverrides {
	open(SO,"$admindir/statoverride") || &quit(sprintf(_g("cannot open statoverride: %s"), $!));
	while (<SO>) {
		my ($owner,$group,$mode,$file);
		chomp;

		($owner,$group,$mode,$file)=split(' ', $_, 4);
		die sprintf(_g("Multiple overrides for \"%s\", aborting"), $file)
			if defined $owner{$file};
		$owner{$file}=$owner;
		$group{$file}=$group;
		$mode{$file}=$mode;
	}
	close(SO);
}


sub WriteOverrides {
	my ($file);

	open(SO,">$admindir/statoverride-new") || &quit(sprintf(_g("cannot open new statoverride file: %s"), $!));
	foreach $file (keys %owner) {
		print SO "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
	close(SO);
	chmod(0644, "$admindir/statoverride-new");
	unlink("$admindir/statoverride-old") ||
		$! == ENOENT || &quit(sprintf(_g("error removing statoverride-old: %s"), $!));
	link("$admindir/statoverride","$admindir/statoverride-old") ||
		$! == ENOENT || &quit(sprintf(_g("error creating new statoverride-old: %s"), $!));
	rename("$admindir/statoverride-new","$admindir/statoverride")
		|| &quit(sprintf(_g("error installing new statoverride: %s"), $!));
}


sub quit { printf STDERR _g("dpkg-statoverride: %s")."\n", "@_"; exit(2); }
sub badusage { printf STDERR _g("dpkg-statoverride: %s")."\n\n", "@_"; print(_g("You need --help.")."\n"); exit(2); }

# vi: ts=8 sw=8 ai si cindent
