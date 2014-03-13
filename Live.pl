#!/usr/bin/perl

package Live;

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;

use Load;
use Project;

#autoflush
$| = 1;

#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------

my $infile = $ARGV[0];
print "Opening : $infile\n";
Load::LoadStoredProject($infile);
our $project;

print "--------- Starting Project $project->{globals}{name} ---------\n";

$project->Start;

