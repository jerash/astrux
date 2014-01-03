#!/usr/bin/perl
use strict;
use warnings;

#use Config::IniFiles;
 
############################# VERIFY PROJECT ####################################
print "\n### Project tests ###\n\n";

my $mixer = './mixer.ecs';
my $plumbing = './jack.plumbing';

#verify project files availability
die "Main acasound mixer not found, exiting\n" unless (-e $mixer);
print "Main ecasound mixer found\n";
die "jack.plumbing file not found, exiting\n" unless (-e $plumbing);
print "jack.plumbing file found\n";

############################## VERIFY SONGS #####################################
print "\n### Songs tests ###\n\n";

#get the song folder names into an array
opendir my($directory), "." or die "Can't open dir .\n";
my @songlist = grep { /^[0-9][0-9].*/ } readdir($directory);
closedir $directory;
#display the number of songs we found
my $numberofsongs = @songlist;
print $numberofsongs . " songs have been found\n";

#verify if there is something to be done
die "No songs have been found, exiting\n" until ($numberofsongs > 0);

#verify songs integrity
my $index=0;
foreach my $folder(@songlist) {
	#check directory for known files
	opendir $directory, $folder or die "Can't open dir .\n";
	my @files = grep { /ecs/ || /wav/ || /mid/ || /lscp/ } readdir($directory);
	closedir $directory;
	if (@files) {
		print "Files ok for song " . $folder . "\n";
	}
	else {
		print "No files found in song " . $folder . "\n";
		#removing this song from the list
		$songlist[$index]="";
	}
	$index++;
}

#cleanup songs list
my @validsonglist;
foreach(@songlist){
    if( ( defined $_) and !($_ =~ /^$/ )){
        push(@validsonglist, $_);
    }
}

undef @songlist;

#display the number of valid songs
$numberofsongs = @validsonglist;
print $numberofsongs . " valid songs found \n";

#verify if there is any valid songs left
die "No more valid songs, exiting\n" until ($numberofsongs > 0);

############################## RESULTS #####################################

print "\n PROJECT IS VALID\n";
exit(0);
