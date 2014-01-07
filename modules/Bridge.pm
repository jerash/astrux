#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini";
die "reading project ini file failed\n" until $ini_project;
#folder where to store generated files
my $files_folder = $ini_project->val('project','output_path');
#--------------------------------------------------------------------

# sub new {
      # my $class = shift;
      # open my $file, ">$files_folder/oscmidistate.csv" or die $!;
      # bless $file, $class;
      # return $file;
# }

sub Init_file {
	open FILE, ">$files_folder/oscmidistate.csv" or die $!;
	print FILE "path;value;min;max;CC;channel\n";
}

sub Add_to_file {
	open FILE, ">>$files_folder/oscmidistate.csv" or die $!;
	print FILE shift;
	close FILE;
}

sub Close_file {
	close FILE;
}

1;