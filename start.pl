#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/seijitsu/astrux/modules';
use Project;
use Live;

use Data::Dumper;

#----------------------------------------------------------------
# This is the main tool for Astrux Live
#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------
#my $Live = Project->load($);
#print " -- Live Project Loaded :) --\n" if defined $Live;

my $infile = $ARGV[0];
print "file to open : $infile\n";

use Storable;
my $Live = retrieve($infile);

#----------------------------------------
$Live->Live::Start;

#------------Now PLay !------------------------
my $do_save = $Live->Live::PlayIt;

#back here is we need to exit
if ($do_save) {
	print "Saving state...\n";
	$Live->SaveTofile("$Live->{project}{name}".".cfg");
}

print "\n";
