#!/usr/bin/perl

package Song;

use strict;
use warnings;
use Config::IniFiles;
use Audio::SndFile;
#http://search.cpan.org/~jdiepen/Audio-SndFile-0.09/lib/Audio/SndFile.pm

use Data::Dumper;

sub new {
	my $class = shift;
	my $folder = shift;

	#init structure
	my $song = {};
	
	bless $song,$class;

	#get files list
	my @songfiles = <$folder/*.*>;

	#look for the ini file first
	foreach my $file (@songfiles) {
		#ignore directories, use files only
		next unless ((-e $file) and ($file =~ /.*song.ini$/));

		print " |_Song: Create song from $file\n";
		#create a song object
		$song->init($file,$folder);
	}		

	return $song; 
}

sub init {
	#grap song object from argument
	my $song = shift;
	my $ini_file = shift;
	my $folder = shift;

	#ouverture du fichier ini de configuration des channels
	tie my %songinfo, 'Config::IniFiles', ( -file => $ini_file );
	die "reading I/O ini file failed\n" until %songinfo;
	my $songinfo_ref = \%songinfo;

	#verify in [song_globals] section exists
	if (!$songinfo_ref->{song_globals}) {
		die "missing [song_globals] section in $ini_file song file\n";
	}

	#update song structure
	%{$song} = %songinfo;

	#TODO consider to add the channels info at ini creation !!
	#for each player slot, check file parameters for mono/stereo
	foreach my $section (keys %{$song}) {

		#only match audio players, and catch payer slot number
		next unless (($section =~ /^players_slot_(\d+)/) and ($song->{$section}{type} eq "player"));
		my $slotnumber = $1;
		#print "matched:$section with number $slotnumber\n";

		#create path to file
		my $filename = $folder."/".$song->{$section}{filename};
		
		#open file
		my $wavfile = Audio::SndFile->open("<","$filename");
		
		#TODO check samplerate and bit definition, but ecasound can deal with it correctly for now
		
		#add number of channels to structure
		$song->{$section}{channels} = $wavfile->channels;
		print "   |_found ".$song->{$section}{channels}." channel(s) in wav file $filename\n";

		#create ecs line for mono file
		$song->{$section}{ecsline} = "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack,,slot_$slotnumber" if $song->{$section}{channels} eq 1;
		#create ecs line for stereo file
		$song->{$section}{ecsline} = "-a:$slotnumber -i:$filename -o:jack,,slot_$slotnumber" if $song->{$section}{channels} eq 2;
		#TODO evaluate beter integration
	}
}

sub build_song_header {
	my $song = shift;
print "building...";
	#print "--song:build_header\n header = $header\n";
	die "ecs file has not been created" if ($song->{ecasound}{status} eq "notcreated");
	#open file handle
	open my $handle, ">>$song->{ecasound}{ecsfile}" or die $!;
	#append to file
	print $handle $song->{ecasound}{header} or die $!;
	#close file
	close $handle or die $!;
	#update status
	$song->{ecasound}{status} = "header";
}
sub add_songfile_chain {
	my $song = shift;
print "adding...";
	#open file in add mode
	open my $handle, ">>$song->{ecasound}{ecsfile}" or die $!;
	print $handle "\n";
	foreach my $section (sort keys %{$song}) {
		#only match audio players, and catch payer slot number
		next unless (($section =~ /^players_slot_/) and ($song->{$section}{type} eq "player"));
		#append to file
		print $handle $song->{$section}{ecsline};
		print $handle "\n";
	}	
	#close file
	close $handle or die $!;
	#update status
	$song->{ecasound}{status} = "created";
}

1;