#!/usr/bin/perl

package Song;

use strict;
use warnings;
use Config::IniFiles;
use Audio::SndFile;
#http://search.cpan.org/~jdiepen/Audio-SndFile-0.09/lib/Audio/SndFile.pm

use Data::Dumper;

###########################################################
#
#		 SONG OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $folder = shift;
	die "Song Error: can't create song without a folder path\n" unless $folder;

	#init structure
	my $song = {
		"path" => $folder
	};
	
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
	die "Song Error: reading I/O ini file failed\n" unless %songinfo;
	my $songinfo_ref = \%songinfo;

	#verify in [song_globals] section exists
	if (!$songinfo_ref->{song_globals}) {
		die "Song Error: missing [song_globals] section in $ini_file song file\n";
	}

	#update song structure with globals
	foreach my $key (keys $songinfo_ref->{song_globals}) {
		$song->{$key} = $songinfo_ref->{song_globals}{$key};
	}
	delete $songinfo_ref->{song_globals};

	#for each player slot, check file parameters for mono/stereo
	foreach my $section (keys %{$songinfo_ref}) {

		# match audio players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "audio_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^players_slot_(\d+)/;
			my $slotnumber = $1;
			$song->{audio_files}{$section} = $songinfo_ref->{$section};
			$song->{audio_files}{$section}{slot} = $slotnumber; 
		}
		# match midi players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "midi_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^MIDI_(\d+)/;
			my $slotnumber = $1;
			$song->{midi_files}{$section} = $songinfo_ref->{$section};
			$song->{midi_files}{$section}{slot} = $slotnumber; 
		}
		# match sampler
		if ($songinfo_ref->{$section}{type} eq "sampler") {
			$song->{sampler_files}{$section} = $songinfo_ref->{$section};
		}

		# #create ecs line for mono file
		# $song->{$section}{ecsline} = "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack,,slot_$slotnumber" if $song->{$section}{channels} eq 1;
		# #create ecs line for stereo file
		# $song->{$section}{ecsline} = "-a:$slotnumber -i:$filename -o:jack,,slot_$slotnumber" if $song->{$section}{channels} eq 2;
	}
}

###########################################################
#
#			ECASOUND functions
#
###########################################################

sub build_songfile_chain {
	my $song = shift;

	my @chains;
	foreach my $section (sort keys %{$song->{audio_files}}) {

		#only match audio players, and catch player slot number
		next unless (($section =~ /^players_slot_(\d+)/) and ($song->{audio_files}{$section}{type} eq "audio_player"));
		my $slotnumber = $1;
		#create path to file
		my $filename = $song->{path} . "/" . $song->{audio_files}{$section}{filename};
		#create ecs line for mono file
		push @chains , "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 1;
		#create ecs line for stereo file
		push @chains , "-a:$slotnumber -i:$filename -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 2;

	}
	#add chains to song
	$song->{ecasound}{io_chains} = \@chains;
}

1;