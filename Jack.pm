#!/usr/bin/perl

package Jack;

use strict;
use warnings;

sub get_jack_hardware_io_list {

	my $hardware_io_list;
	my @buffer = `jack_lsp -pt`;
	while (my $line = shift @buffer) {
		chomp $line;
		my $properties = shift @buffer;
		my $type = shift @buffer;
		push @{$hardware_io_list->{hardware_audio_inputs}} , $line if ($properties =~ /output/) and ($properties =~ /physical/) and ($type =~ /audio/);
		push @{$hardware_io_list->{hardware_audio_outputs}} , $line if ($properties =~ /input/) and ($properties =~ /physical/) and ($type =~ /audio/);
		push @{$hardware_io_list->{hardware_midi_inputs}} , $line if ($properties =~ /output/) and ($properties =~ /physical/) and ($type =~ /midi/);
		push @{$hardware_io_list->{hardware_midi_outputs}} , $line if ($properties =~ /input/) and ($properties =~ /physical/) and ($type =~ /midi/);
	}
	return $hardware_io_list;
}

sub get_jack_io_list_by_type {

	my $io_list;
	my @buffer = `jack_lsp -pt`;
	while (my $line = shift @buffer) {
		chomp $line;
		my $properties = shift @buffer;
		my $type = shift @buffer;
		push @{$io_list->{hardware_audio_inputs}} , $line if ($properties =~ /output/) and ($properties =~ /physical/) and ($type =~ /audio/);
		push @{$io_list->{hardware_audio_outputs}} , $line if ($properties =~ /input/) and ($properties =~ /physical/) and ($type =~ /audio/);
		push @{$io_list->{hardware_midi_inputs}} , $line if ($properties =~ /output/) and ($properties =~ /physical/) and ($type =~ /midi/);
		push @{$io_list->{hardware_midi_outputs}} , $line if ($properties =~ /input/) and ($properties =~ /physical/) and ($type =~ /midi/);
		push @{$io_list->{software_audio_inputs}} , $line if ($properties =~ /input/) and ($properties !~ /physical/) and ($type =~ /audio/);
		push @{$io_list->{software_audio_outputs}} , $line if ($properties =~ /output/) and ($properties !~ /physical/) and ($type =~ /audio/);
		push @{$io_list->{software_midi_inputs}} , $line if ($properties =~ /input/) and ($properties !~ /physical/) and ($type =~ /midi/);
		push @{$io_list->{software_midi_outputs}} , $line if ($properties =~ /output/) and ($properties !~ /physical/) and ($type =~ /midi/);
	}
	return $io_list;
}

1;
