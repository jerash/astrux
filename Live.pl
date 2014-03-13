#!/usr/bin/perl

package Live;

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;

use Load;
use Project;
use Mixer;
use Song;
use Bridge;
use Utils;

###########################################################
#
#		 INIT LIVE
#
###########################################################

#autoflush
$| = 1;

#----------------------------------------------------------------
# This is the main entry point for Astrux Live
#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------

my $infile = $ARGV[0];
print "Opening : $infile\n";
Load::LoadStoredProject($infile);
our $project;

print "--------- Start Project $project->{globals}{name} ---------\n";

$project->Start;

