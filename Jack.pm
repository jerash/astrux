#!/usr/bin/perl

package Jack;

use strict;
use warnings;

sub Start {
	my $project = shift;
	$project->Start_Jack_Server;
	$project->Start_Jack_OSC;
}

sub Stop {
	my $project = shift;
	$project->Stop_Jack_Server;
	$project->Stop_Jack_OSC;
}

sub Start_Jack_Server {
	my $project = shift;

	# JACK server
	#---------------------------------
	my $pid_jackd = qx(pgrep jackd);
	if (!$pid_jackd) {
		print "Strange ...JACK server is not running ?? Starting it\n";
		my $command = "$project->{jack}{start} 2>&1 &";
		system ($command) if $command;
		sleep 1;
		$pid_jackd = qx(pgrep jackd);
	}
	else {
		print "JACK server running with PID $pid_jackd";
		#verify jack parameters
		my $params = qx(ps $pid_jackd);
		die "JACK server doesn't have project parameters, please check.\nExpected : $project->{jack}{start}\nFound :\n$params"
			unless $params =~ $project->{jack}{start};
		print "JACK server parameters ok\n";
	}
	$project->{JACK}{PID} = $pid_jackd;
}

sub Start_Jack_OSC {
	my $project = shift;

	# JACK OSC
	#---------------------------------
	my $pid_jackosc;
	my $port_jackosc;
	my @lines = qx(pgrep -a jack-osc);
	if ($project->{'jack-osc'}{enable}) {
		if ($#lines > 0) {
			die "Error: multiple jack-osc instances found\n";
		}
		elsif ($#lines == -1) {
			print "jack-osc server is not running, starting it on oscport $project->{'jack-osc'}{osc_port}\n";
			my $command = "jack-osc -p $project->{'jack-osc'}{osc_port} >/dev/null 2>&1 &";
			system ($command);
			sleep 1;
			$pid_jackosc = qx(pgrep jack-osc);
			chomp $pid_jackosc;
			die "Jack error: could not start jack-osc\n" unless $pid_jackosc;
		}
		elsif ($#lines == 0) {
			if ( $lines[0] =~ /(\d+?) jack-osc -p (\d+?)$/ ) {
				$pid_jackosc = $1;
				$port_jackosc = $2;
				die "jack-osc is not running on the expected oscport : $lines[0]\n" unless $port_jackosc eq $project->{'jack-osc'}{osc_port};
			}
			else {
				die "jack-osc doesn\'t have expected parameters : $lines[0]\n";
			}
		}
		print "jack-osc server running with PID $pid_jackosc on oscport $project->{'jack-osc'}{osc_port}\n";
		$project->{'jack-osc'}{PID} = $pid_jackosc;
	}
}

sub Stop_Jack_OSC {
	my $project = shift;

	return unless $project->{'jack-osc'}{enable};
	# by PID
	if (defined $project->{'jack-osc'}{PID}) {
		print "Stopping jack-osc with PID $project->{'jack-osc'}{PID}\n";
		kill 'KILL',$project->{'jack-osc'}{PID};
	}
	# or brute
	else {
		print "Force killall jack-osc\n";
		my $blob = `killall jack-osc`;
	}
}

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
