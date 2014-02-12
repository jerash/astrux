#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;

use Project;

use Data::Dumper;
use Config::IniFiles;
#http://search.cpan.org/~shlomif/Config-IniFiles-2.82/lib/Config/IniFiles.pm


#----------------------------------------------------------------
# This is the main tool for Astrux Live
#----------------------------------------------------------------

print "\n\n\n
--------------------------------
 ASTRUX Live Project Generation
--------------------------------\n\n";

my $infile = "";
if ($#ARGV+1 eq 0) {
	#project ini file is in the current folder
	print "No argument, trying to find a project file in current folder\n";
	$infile = "project.ini" if (-e "./project.ini");
}
elsif ($#ARGV+1 eq 1) {
	#argument passed, assume it to be the project file
	$infile = $ARGV[0];
	print "Opening : $infile\n";
}
die "could not load project file\n" if $infile eq "";

#create the ini hash from the file
my %ini_project;
tie %ini_project, 'Config::IniFiles', ( -file => $infile );
die "reading project ini file failed\n" unless %ini_project;
my $ini_project_ref = \%ini_project;

#------------Create project structure----------------------------
#TODO build the base_path here
my $Live = Project->new($ini_project_ref);
die "Failed to create Project!!!\n" unless defined $Live;
print "
---------------------------
Live Project Generation OK
---------------------------\n\n";

#------------Create project files------------------------
$Live->GenerateFiles;
$Live->SaveTofile("$Live->{project}{name}");

print " 
---------------------------
-- Live Project Saved :) --
---------------------------\n\n";

#print Dumper $Live;