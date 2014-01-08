#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/seijitsu/astrux/modules';
use Project;
use Bridge;
use Plumbing;

use Config::IniFiles;
#http://search.cpan.org/~shlomif/Config-IniFiles-2.82/lib/Config/IniFiles.pm
use Audio::SndFile;

#----------------------------------------------------------------
# This is the main tool for Astrux Live
#----------------------------------------------------------------

#project ini file is in the current folder
my %ini_project;
tie %ini_project, 'Config::IniFiles', ( -file => "project.ini" );
die "reading project ini file failed\n" until %ini_project;
my $ini_project_ref = \%ini_project;

#----------------------------------------------------------------
#create the project
my $Live = Project->new($ini_project_ref);

#generate the files for the live
#$Live->Generate; <<inutile intégrer dans new

print "\n";

