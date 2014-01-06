#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/seijitsu/astrux/modules';
require ("MidiCC.pm");
require ("Bridge.pm");
require ("Plumbing.pm");
require ("Mixer.pm");
require ("Project.pm");

#----------------------------------------------------------------
# This script will create a main mixer ecs file for ecasound based on the information contained in ini files
# It will unconditionnaly overwrite any previoulsy existing ecs file with the same name.
# it is to be launched in the project folder root.
#----------------------------------------------------------------
my $debug = 0;

use Data::Dumper;
use Config::IniFiles;
#http://search.cpan.org/~shlomif/Config-IniFiles-2.82/lib/Config/IniFiles.pm
use Audio::SndFile;

#-----------------------PROJECT INI---------------------------------
#project file
my %ini_project;
tie %ini_project, 'Config::IniFiles', ( -file => "project.ini" );
die "reading project ini file failed\n" until %ini_project;
my $project_ref = \%ini_project;
#my $ini_project = new Config::IniFiles -file => "project.ini";
#bless $project_ref, "Config::IniFiles";
#Generate project from ini file
Project::from_inifile($project_ref);

print "\n";

