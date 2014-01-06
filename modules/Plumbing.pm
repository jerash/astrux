#!/usr/bin/perl

package Plumbing;

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
#do we generate plumbing file ?
my $do_plumbing = $ini_project->val('jack.plumbing','enable');
#--------------------------------------------------------------------

sub new {
      my $class = shift;
      open my $file, ">$files_folder/jack.plumbing" or die $!;
      bless $file, $class;
      return $file;
}
  
sub Add {
	if ($do_plumbing){ 
		my $file = shift;
		my $message = shift;
		print $file $message . "\n";
	}	
}
sub Close {
	close shift;
}

1;