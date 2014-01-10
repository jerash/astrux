#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/seijitsu/astrux/modules';
use Project;
use Plumbing;

use Data::Dumper;
use Config::IniFiles;
#http://search.cpan.org/~shlomif/Config-IniFiles-2.82/lib/Config/IniFiles.pm
#----------------------------------------------------------------
# This is the main tool for Astrux Live
#----------------------------------------------------------------

#TODO : if no arguments check for config.ini in current folder
#		else, parse command line arguments

#project ini file is in the current folder
my %ini_project;
tie %ini_project, 'Config::IniFiles', ( -file => "project.ini" );
die "reading project ini file failed\n" until %ini_project;
my $ini_project_ref = \%ini_project;

#------------Create project structure----------------------------
my $Live = Project->new($ini_project_ref);

print " -- Live Created sucessfully :) --\n" if defined $Live;

#------------Create ecasound files------------------------
$Live->CreateEcsFiles;	

#generate the files for the live
#$Live->Generate; 

#Now PLay !

#print Dumper $Live;
 
# use Storable;
# store $Live, 'tree.stor';
# $hashref = retrieve('file');
#>>>works but output is not readable

#Save
$Data::Dumper::Purity = 1;
open FILE, ">project.cfg" or die "Can't open 'tree':$!";
print FILE Dumper $Live;
close FILE;
#restore
# open FILE, $infile;
# undef $/;
# eval <FILE>;
# close FILE;


print "\n";
