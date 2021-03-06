#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;
use Cwd;
use Cwd 'abs_path';

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

my $pathtoproject = "";
my $base_path = "";

#------------ Parse arguments ----------------------------

if ($#ARGV+1 eq 0) {
	#we should be in the project base folder, are we ?
	print "No argument, trying to find a project file\n";
	$pathtoproject .= "project/project.ini";
	#update the base path with the current directory
	$base_path = getcwd;
}
elsif ($#ARGV+1 eq 1) {
    #argument passed, assume it to be the project base folder
	$pathtoproject .= $ARGV[0] . "project/project.ini";
	#update the base path with the absolute directory
	$base_path = abs_path($ARGV[0]);
}

#------------ parse ini file to object -------------------------

#transforming project file to an absolute path
$pathtoproject = abs_path($pathtoproject);
die "could not find project file $pathtoproject\n" unless (-e $pathtoproject);

print "Project base path is set to : $base_path\n";

#trying to create the ini hash from the file
my %ini_project;
tie %ini_project, 'Config::IniFiles', ( -file => $pathtoproject );
die "reading project ini file failed\n" unless %ini_project;

#add project base folder
$ini_project{globals}{base_path} = $base_path;

print "Project init from file : $pathtoproject\n";
my $ini_project_ref = \%ini_project;

#------------Create project structure----------------------------
our $project = Project->new($ini_project_ref);
die "Failed to create Project!!!\n" unless defined $project;

print "
---------------------------
   Project Generation OK
---------------------------\n\n";

#----------Remove old project files------------------

$project->RemoveOldFiles;

#------------Create project files------------------------

$project->GenerateFiles;
$project->SaveToFile;

print " 
---------------------------
--    Project Saved :)   --
---------------------------\n\n";

#print Dumper $project;