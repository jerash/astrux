#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini";
die "reading project ini file failed\n" until $ini_project;
#folder where to store generated files
my $files_folder = $ini_project->val('project','filesfolder');
#--------------------------------------------------------------------

sub new {
	my $class = shift;
	open my $file, ">$files_folder/mixer.ecs" or die $!;
	bless $file, $class;
	return $file;
}

sub build_header {

}

sub from_inifile {

}

1;