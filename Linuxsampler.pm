#!/usr/bin/perl

package Linuxsampler;

use strict;
use warnings;

###########################################################
#
#		 LINUXSAMPLER OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $sampler = shift;
	die "Linuxsampler Error: can't create sampler without options\n" unless $sampler;

	#init structure
	bless $sampler,$class;

	return $sampler;
}

sub Start {
	my $sampler = shift;

	my $pid_linuxsampler;
	my $port_linuxsampler;
	my @lines = qx(pgrep -a linuxsampler);
	if ($sampler->{enable}) {
		if ($#lines > 0) {
			die "Error: multiple linuxsampler instances found\n";
		}
		elsif ($#lines == -1) {
			print "linuxsampler server is not running, starting it on port $sampler->{port}\n";
			my $command = "linuxsampler --lscp-port $sampler->{port} >/dev/null 2>&1 &";
			system ($command);
			sleep 1;
			$pid_linuxsampler = qx(pgrep linuxsampler);
			chomp $pid_linuxsampler;
			die "Error: could not start linuxsampler\n" unless $pid_linuxsampler;
		}
		elsif ($#lines == 0) {
			if ( $lines[0] =~ /(\d+?) linuxsampler --lscp-port (\d+?)$/ ) {
				$pid_linuxsampler = $1;
				$port_linuxsampler = $2;
				die "linuxsampler is not running on the expected port : $lines[0]\n" unless $port_linuxsampler eq $sampler->{port};
			}
			else {
				die "linuxsampler doesn\'t have expected parameters : $lines[0]\n";
			}
		}
		print "linuxsampler server running with PID $pid_linuxsampler on port $sampler->{port}\n";
		$sampler->{PID} = $pid_linuxsampler;
	}
}

sub Stop {
	my $sampler = shift;
	return unless $sampler->{enable};
	# by PID
	if (defined $sampler->{PID}) {
		print "Stopping linuxsampler with PID $sampler->{PID}\n";
		kill 'KILL',$sampler->{PID};
	}
	# or brute
	else {
		print "Force killall linuxsampler\n";
		my $blob = `killall linuxsampler`;
	}
}

###########################################################
#
#		 LINUXSAMPLER OBJECT functions
#
###########################################################

1;