#!/usr/bin/perl

package Song;

use strict;
use warnings;

use Midifile;

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

	#for each player slot, check file type
	foreach my $section (keys %{$songinfo_ref}) {

		# match audio players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "audio_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^players_slot_(\d+)/;
			my $slotnumber = $1;
			$song->{audio_files}{$section} = $songinfo_ref->{$section};
			$song->{audio_files}{$section}{slot} = $slotnumber; 
			print " |_Song: adding audio player for file $songinfo_ref->{$section}{filename}\n";
		}
		# match midi players, and catch player slot number
		if ($songinfo_ref->{$section}{type} eq "midi_player") {
			die "Song Error: Bad format on section name : $section\n" unless $section =~ /^MIDI_(\d+)/;
			my $slotnumber = $1;
			$song->{midi_files}{$section} = $songinfo_ref->{$section};
			$song->{midi_files}{$section}{slot} = $slotnumber; 
			print " |_Song: adding midi player for file $songinfo_ref->{$section}{filename}\n";
		}
		# match sampler
		if ($songinfo_ref->{$section}{type} eq "sampler") {
			$song->{sampler_files}{$section} = $songinfo_ref->{$section};
			print " |_Song: adding sampler file $songinfo_ref->{$section}{filename}\n";
		}
	}
}

###########################################################
#
#		 SONG functions
#
###########################################################

sub add_markers {
	my $song = shift;
	my $output_path = shift;

	foreach my $midifilename (keys %{$song->{midi_files}}) {
		next unless ((defined $song->{midi_files}{$midifilename}{time_master}) and ($song->{midi_files}{$midifilename}{time_master} eq 1));
		my $midifile = $output_path . "/$song->{midi_files}{$midifilename}{filename}";
		print " |_Song: adding midi markers from file $midifile\n";
		my @songevents = MidiFile::get_timed_metaevents($midifile);
		return unless @songevents;
		$song->{markers} = \@songevents;
	}
}

sub save_markers_file {
	my $song = shift;
	my $output_path = shift;

	return unless exists $song->{markers};
	$song->{markers_file} = $output_path . "/markers.csv";
	print " |_Song: creating markers file $song->{markers_file}\n";
	open FILE,">$song->{markers_file}" or die "$!";
	print FILE "$_->[0];$_->[1];$_->[2];$_->[3]\n" for @{$song->{markers}};
	close FILE;
}

sub save_klick_tempomap_file {
	my $song = shift;
	my $output_path = shift;
	return unless $output_path;

	my @file_lines = ();
	my ($last_change,$nb_bars) = (0,0);
	my ($current_tempo,$current_timesignature);

	# get tempomap infos from stored meta events
	foreach my $line (@{$song->{markers}}) {
		# print "---$line";
		my @parts = @{$line};
		my @times = split(":",$parts[1]);
		if ($parts[2] eq "set_tempo") {
			warn "SONG WARNING: tempo changes outside beginning of measure is incompatible with klick, may be inaccurate\n"
				if (($times[1] ne 0)or($times[2] ne 0));
			$current_tempo = $parts[3] if $times[0] eq 0;
			$nb_bars = $times[0] - $last_change;
			push @file_lines , "$nb_bars $current_tempo" if $times[0] ne 0;
			$current_tempo = $parts[3] if $times[0] ne 0;
			$last_change = $times[0];
		}
		elsif ($parts[2] eq "time_signature") {
			warn "SONG WARNING: time signature changes outside beginning of measure is incompatible with klick, may be inaccurate\n"
				if (($times[1] ne 0)or($times[2] ne 0));
			$current_timesignature = $parts[3] if $times[0] eq 0;
			$nb_bars = $times[0] - $last_change;
			push @file_lines , "$nb_bars $current_timesignature $current_tempo" if $times[0] ne 0;
			$current_timesignature = $parts[3] if $times[0] ne 0;
			$last_change = $times[0];
		}
	}

	# if we have found necessary info in meta events
	if (defined $current_tempo and defined $current_timesignature and $#file_lines eq -1) {
		# we're missing song length in bars, try to get it from any last event
		my $last_nb = $#{$song->{markers}};
		my $last = ${$song->{markers}}[$last_nb];
		my @bars = split(":",$last->[1]);
		# if we don't have other event, then force 999 bars
		($bars[0] eq 0) ? push @file_lines , "999 $current_timesignature $current_tempo" :
						push @file_lines , "$bars[0] $current_timesignature $current_tempo";
	}
	# else check if we have static tempomap information in song 
	elsif ((defined $song->{metronome_tempo}) and (defined $song->{metronome_timesignature})) {
		push @file_lines , "999 $song->{metronome_timesignature} $song->{metronome_tempo}";
	}

	# dont create file if we have nothing to write
	return unless $#file_lines ge 0;

	# or generate a tempomap file when we have info from any manner
	$song->{klick_file} = $output_path . "/tempo.map";
	print " |_Song: creating tempomap(klick) file $song->{klick_file}\n";
	open FILE,">$song->{klick_file}" or die "$!";
	print FILE "$_\n" for @file_lines;
	close FILE;
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
		# push @chains , "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 1;
		#create ecs line for stereo file
		# push @chains , "-a:$slotnumber -i:$filename -o:jack,,slot_$slotnumber" if $song->{audio_files}{$section}{channels} eq 2;

		# we create an autoconnect output because jackplumbing sometimes can't see that the port has changed
		push @chains , "-a:$slotnumber -i:$filename -chcopy:1,2 -o:jack_multi,$song->{audio_files}{$section}{connect_1},$song->{audio_files}{$section}{connect_2}";
	}
	#add chains to song
	$song->{ecasound}{io_chains} = \@chains;
}

1;