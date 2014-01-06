#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini"; # -allowempty => 1;
die "reading project ini file failed\n" until $ini_project;
#folder where to store generated files
my $files_folder = $ini_project->val('project','filesfolder');


sub add_to_bridgefile {
	open FILE, ">>$files_folder/oscmidistate.csv" or die $!;
	print FILE shift;
	close FILE;
}