#!/usr/bin/perl

package Metronome;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $metronome = shift;
	die "Metronome Error: can't create metronome without options\n" unless $metronome;

	#init structure
	bless $metronome,$class;

	return $metronome; 
}

sub Start {
	my $metronome = shift;
	return unless $metronome->{enable};

	if ($metronome->{engine} eq "klick") {
		$metronome->start_klick;
	}
}

sub start_klick {
	my $metronome = shift;

	my $pid_klick;
	my $port_klick;
	my @lines = qx(pgrep -a klick);
	if ($#lines > 0) {
		die "Error: multiple klick instances found\n";
	}
	elsif ($#lines == -1) {
		print "klick is not running, starting it on oscport $metronome->{osc_port}\n";
		my $command = "klick -o $metronome->{osc_port} -t -T >/dev/null 2>&1 &";
		system ($command);
		sleep 1;
		$pid_klick = qx(pgrep klick);
		chomp $pid_klick;
		die "Metronome error: could not start klick\n" unless $pid_klick;
	}
	elsif ($#lines == 0) {
		if ( $lines[0] =~ /(\d+?) klick -o (\d+?) -t -T$/ ) {
			$pid_klick = $1;
			$port_klick = $2;
			die "klick is not running on the expected oscport : $lines[0]\n" unless $port_klick eq $metronome->{osc_port};
		}
		else {
			die "klick doesn\'t have expected parameters : $lines[0]\n";
		}
	}
	print "klick running with PID $pid_klick on oscport $metronome->{osc_port}\n";
	$metronome->{PID} = $pid_klick;
}

sub stop_klick {
	# body...
}

1;