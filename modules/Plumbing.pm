#!/usr/bin/perl

package Plumbing;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
# my $ini_project = new Config::IniFiles -file => "project.ini";
# die "reading project ini file failed\n" until $ini_project;
# #folder where to store generated files
# #do we generate plumbing file ?
# my $do_plumbing = $ini_project->val('jack.plumbing','enable');
#--------------------------------------------------------------------

sub new {
	my $class = shift;
	my $ini_project = shift;
	if ( $ini_project->val('jack.plumbing','enable') == 1 ) {
		my $files_folder = $ini_project->val('project','filesfolder');
		open my $file, ">$files_folder/jack.plumbing" or die $!;
		bless $file, $class;
		return $file;
  	} else {
  		warn "Plumbing not activated!!\n";
  		return undef;
  	}
}
  
sub Add {
	if (my $file = shift) {
		my $message = shift;
		print $file $message . "\n";
	} else {
		warn "Plumbing not activated!!\n";
	}
}
sub Close {
	close shift;
}

1;