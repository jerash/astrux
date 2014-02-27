#!/usr/bin/perl

package Song;

use strict;
use warnings;

use MidiFile;

###########################################################
#
#		 SONG OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $file = shift;
	die "Song Error: can't create song without an ini file\n" unless $file;

	#init structure
	my $song = {
		"ini_file" => $file
	};
	
	bless $song,$class;
	
	#fill from ini file 
	$song->init($file);

	return $song; 
}

sub init {
	#grap song object from argument
	my $song = shift;
	my $ini_file = shift;

	use Config::IniFiles;
	#ouverture du fichier ini de configuration des channels
	tie my %songinfo, 'Config::IniFiles', ( -file => $ini_file );
	die "Song Error: reading I/O ini file failed\n" unless %songinfo;
	my $songinfo_ref = \%songinfo;

	#verify in [song_globals] section exists
	die "Song Error: missing [song_globals] section in $ini_file song file\n" if (!$songinfo_ref->{song_globals});
	
	#update song structure with globals
	$song->{$_} = $songinfo_ref->{song_globals}{$_} foreach (keys $songinfo_ref->{song_globals});
	delete $songinfo_ref->{song_globals};

	#for each player slot, check file parameters for mono/stereo
	foreach my $section (keys %{$songinfo_ref}) {

		# match audio players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "audio_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^players_slot_(\d+)/;
			my $slotnumber = $1;
			$song->{audio_files}{$section} = $songinfo_ref->{$section};
			$song->{audio_files}{$section}{slot} = $slotnumber; 
			print " |_Song: adding player for file $songinfo_ref->{$section}{filename}\n";
		}
		# match midi players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "midi_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^MIDI_(\d+)/;
			my $slotnumber = $1;
			$song->{midi_files}{$section} = $songinfo_ref->{$section};
			$song->{midi_files}{$section}{slot} = $slotnumber; 
			print " |_Song: adding player for file $songinfo_ref->{$section}{filename}\n";
		}
		# match sampler
		if ($songinfo_ref->{$section}{type} eq "sampler") {
			$song->{sampler_files}{$section} = $songinfo_ref->{$section};
			print " |_Song: sampler file $songinfo_ref->{$section}{filename}\n";
		}
	}
}

sub create_markers_file {
	my $song = shift;
	my $output_path = shift;

	foreach my $midifilename (keys %{$song->{midi_files}}) {
		next unless ((defined $song->{midi_files}{$midifilename}{time_master}) and ($song->{midi_files}{$midifilename}{time_master} eq 1));
		my $midifile = $output_path . "/$song->{midi_files}{$midifilename}{filename}";
		my @songevents = MidiFile::get_timed_events($midifile);
		return unless @songevents;
		my $outfilename = $output_path . "/markers.csv";
		print " |_Song: creating markers file $outfilename from $song->{midi_files}{$midifilename}{filename}\n";
		open FILE,">$outfilename" or die "$!";
		print FILE "$_->[0];$_->[1];$_->[2]\n" for @songevents;
		close FILE;
	}
}

###########################################################
#
#			ECASOUND functions
#
###########################################################

sub build_songfile_chain {
	my $song = shift;

	die "missing ini_file info in song $song->{name}\n" unless $song->{ini_file};

	#get folder name from inifile path
	my $path = substr $song->{ini_file} ,0 ,-4;

	my @chains;
	foreach my $section (sort keys %{$song->{audio_files}}) {

		#only match audio players, and catch player slot number
		next unless (($section =~ /^players_slot_(\d+)/) and ($song->{audio_files}{$section}{type} eq "audio_player"));
		my $slotnumber = $1;
		#create path to file
		my $filename = $path . "/" . $song->{audio_files}{$section}{filename};
		#create ecs line for mono file
		push @chains , "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 1;
		#create ecs line for stereo file
		push @chains , "-a:$slotnumber -i:$filename -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 2;

	}
	#add chains to song
	$song->{ecasound}{io_chains} = \@chains;
}

1;