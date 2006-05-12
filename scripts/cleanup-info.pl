#!/usr/bin/perl --
#
#   Clean up the mess that bogus install-info may have done :
#
#	- gather all sections with the same heading into a single one.
#	Tries to be smart about cases and trailing colon/spaces.
#
#   Other clean ups :
#
#	- remove empty sections,
#	- squeeze blank lines (in entries part only).
#
#   Order of sections is preserved (the first encountered section
# counts).
#
#   Order of entries within a section is preserved.
#
# BUGS:
#
#   Probably many : I just recently learned Perl for this program
# using the man pages.  Hopefully this is a short enough program to
# debug.

# don't put that in for production.
# use strict;

my $dpkglibdir = "."; # This line modified by Makefile
push(@INC,$dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg");

my $version = '1.1.6'; # This line modified by Makefile
sub version {
    printf STDERR _g(<<END), $version;
Debian cleanup-info %s.  Copyright (C)1996 Kim-Minh Kaplan.
This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.
END
}

sub usage {
    print STDERR _g(<<'EOF');
usage: cleanup-info [--version] [--help] [--unsafe] [--] [<dirname>]
Warning: the ``--unsafe'' option may garble an otherwise correct file
EOF
}

my $infodir = '/usr/info';
my $unsafe = 0;
$0 =~ m|[^/]+$|;
my $name= $&;

sub ulquit {
    unlink "$infodir/dir.lock"
	or warn sprintf(_g("%s: warning - unable to unlock %s: %s"),
	                $name, "$infodir/dir", $!)."\n";
    die $_[0];
}

while (scalar @ARGV > 0 && $ARGV[0] =~ /^--/) {
    $_ = shift;
    /^--$/ and last;
    /^--version$/ and do {
	version;
	exit 0;
    };
    /^--help$/ and do {
	usage;
	exit 0;
    };
    /^--unsafe$/ and do {
	$unsafe=1;
	next;
    };
    printf STDERR _g("%s: unknown option \`%s'")."\n", $name, $_;
    usage;
    exit 1;
}

if (scalar @ARGV > 0) {
    $infodir = shift;
    if (scalar @ARGV > 0) {
	printf STDERR _g("%s: too many arguments")."\n", $name;
	usage;
	exit 1;
    }
}

if (!link "$infodir/dir", "$infodir/dir.lock") {
    die sprintf(_g("%s: failed to lock dir for editing! %s"),
                $name, $!)."\n".
        ($! =~ /exist/i ? sprintf(_g("try deleting %s"),
                                  "$infodir/dir.lock")."\n" : '');
}
open OLD, "$infodir/dir"
    or ulquit sprintf(_g("%s: can't open %s: %s"),
                      $name, "$infodir/dir", $!)."\n";
open OUT, ">$infodir/dir.new"
    or ulquit sprintf(_g("%s: can't create %s: %s"),
                      $name, "$infodir/dir.new", $!)."\n";

my (%sections, @section_list, $lastline);
my $section="Miscellaneous";	# default section
my $section_canonic="miscellaneous";
my $waitfor = $unsafe ? '^\*.*:' : '^\*\s*Menu';

while (<OLD>) {				# dump the non entries part
    last if (/$waitfor/oi);
    if (defined $lastline) {
	print OUT $lastline
	    or ulquit sprintf(_g("%s: error writing %s: %s"),
	                      $name, "$infodir/dir.new", $!)."\n";
    }
    $lastline = $_;
};

if (/^\*\s*Menu\s*:?/i) {
    print OUT $lastline if defined $lastline;
    print OUT $_;
} else {
    print OUT "* Menu:\n";
    if (defined $lastline) {
	$lastline =~ s/\s*$//;
	if ($lastline =~ /^([^\*\s].*)/) { # there was a section title
	    $section = $1;
	    $lastline =~ s/\s*:$//;
	    $section_canonic = lc $lastline;
	}
    }
    push @section_list, $section_canonic;
    s/\s*$//;
    $sections{$section_canonic} = "\n$section\n$_\n";
}

foreach (<OLD>) {		# collect sections
    next if (/^\s*$/ or $unsafe and /^\*\s*Menu/oi);
    s/\s*$//;
    if (/^([^\*\s].*)/) {		# change of section
	$section = $1;
	s/\s*:$//;
	$section_canonic = lc $_;
    } else {			# add to section
	if (! exists $sections{$section_canonic}) { # create section header
	    push @section_list, $section_canonic;
	    $sections{$section_canonic} = "\n$section\n";
	}
	$sections{$section_canonic} .= "$_\n";
    }
}

eof OLD or ulquit sprintf(_g("%s: read %s: %s"),
                          $name, "$infodir/dir", $!)."\n";
close OLD or ulquit sprintf(_g("%s: close %s after read: %s"),
                            $name, "$infodir/dir", $!)."\n";

print OUT @sections{@section_list};
close OUT or ulquit sprintf(_g("%s: error closing %s: %s"),
                            $name, "$infodir/dir.new", $!)."\n";

# install clean version
unlink "$infodir/dir.old";
link "$infodir/dir", "$infodir/dir.old"
    or ulquit sprintf(_g("%s: can't backup old %s, giving up: %s"),
                      $name, "$infodir/dir", $!)."\n";
rename "$infodir/dir.new", "$infodir/dir"
    or ulquit sprintf(_g("%s: failed to install %s; I'll leave it as %s: %s"),
                      $name, "$infodir/dir", "$infodir/dir.new", $!)."\n";

unlink "$infodir/dir.lock"
    or die sprintf(_g("%s: failed to unlock %s: %s"),
                   $name, "$infodir/dir", $!)."\n";

exit 0;
