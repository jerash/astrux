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

#TODO : if no arguments check for project.ini in current folder
#		else, parse command line arguments
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
print "\nLive Project Generation OK\n";

#------------Create project files------------------------
print "...now generating files\n";
$Live->GenerateFiles;
print "...saving project\n";
$Live->SaveTofile("$Live->{project}{name}");

print " 
---------------------------
-- Live Project Saved :) --
---------------------------\n";

#print Dumper $Live;