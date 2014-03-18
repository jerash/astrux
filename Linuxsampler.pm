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
	# body...
}

sub Start {
	my $project = shift;

	my $pid_linuxsampler;
	my $port_linuxsampler;
	my @lines = qx(pgrep -a linuxsampler);
	if ($project->{linuxsampler}{enable}) {
		if ($#lines > 0) {
			die "Error: multiple linuxsampler instances found\n";
		}
		elsif ($#lines == -1) {
			print "linuxsampler server is not running, starting it on port $project->{linuxsampler}{port}\n";
			my $command = "linuxsampler --lscp-port $project->{linuxsampler}{port} >/dev/null 2>&1 &";
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
				die "linuxsampler is not running on the expected port : $lines[0]\n" unless $port_linuxsampler eq $project->{linuxsampler}{port};
			}
			else {
				die "linuxsampler doesn\'t have expected parameters : $lines[0]\n";
			}
		}
		print "linuxsampler server running with PID $pid_linuxsampler on port $project->{linuxsampler}{osc_port}\n";
		$project->{linuxsampler}{PID} = $pid_linuxsampler;
	}
}

sub Stop {
	my $project = shift;
	return unless $project->{linuxsampler}{enable};
	# by PID
	if (defined $project->{linuxsampler}{PID}) {
		print "Stopping linuxsampler with PID $project->{linuxsampler}{PID}\n";
		kill 'KILL',$project->{linuxsampler}{PID};
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