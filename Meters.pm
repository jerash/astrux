#!/usr/bin/perl

package Meters;

use strict;
use warnings;

# From jack, we're able to have meters for :
#-------------------------------------------
# INPUTS
#	channel_in (main/submix mixer channel from hardware_input/players_out/submix_out/instrument_out)
# OUTPUTS
#	aux_out (main mixer aux out to hardware out port)
#	main_out (main mixer out to hardware out port)
# ROUTINGS
#	channel_out (main/submix mixer channel to main_out/submix_out)
#	channel_aux (main mixer channel to aux monitor)

# Meters project structure
#-------------------------------------------
# {project_root}
#	{meters}
#		backend
#		port
#		PID
#		@{values}
#			jack_port_name	"..."
#			type			channel_in, aux_out ...etc
# 			current_value	[0..1]
# 			current_peak	[0..1]
# 			clip_count 		(may be used as accumulator to trigger clip led if > 3)

# Corresponding osc paths 
#-------------------------------------------
# /mixer/channel/_in_meter_						(channel_in,aux_out,main_out)
# /mixer/channel/_in_peak_
# /mixer/channel/_in_clip_
# /mixer/channel/_out_meter_					(channel_out,aux_out,main_out)
# /mixer/channel/_out_peak_
# /mixer/channel/_out_clip_
# /mixer/channel/aux_to/auxname/_send_meter_			(channel_aux)
# /mixer/channel/aux_to/auxname/_send_peak_
# /mixer/channel/aux_to/auxname/_send_clip_

###########################################################
#
#		 METERS object functions
#
###########################################################

sub new {
	my $class = shift;
	my $options = shift;
	die "Meters Error: can't create meters without options\n" unless $options;

	#init structure
	bless $options,$class;

	return $options; 
}

###########################################################
#
#		 METERS functions
#
###########################################################

sub get_meters_hash {
	my $project = shift;

	#the rule set
	my @meter_values;

	# --- LOOP THROUGH MIXERs ---

	foreach my $mixername (keys %{$project->{mixers}}) {

		#ignore players mixer, we'll get the ports on main mixer player tracks
		next if $project->{mixers}{$mixername}{engine}{name} eq "players";

		# get engine type
		my $engine = $project->{mixers}{$mixername}{engine}{engine};

		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};

		foreach my $channelname (keys %{$mixer}) {

			print " |_Meters: create meters for channel $channelname\n";

			if (($mixer->{$channelname}->is_submix_in)
				or ($mixer->{$channelname}->is_main_in) ) { 

			# --- channel_in ---
				#get the table of input connections
				my @table = @{$mixer->{$channelname}{connect}};
				foreach my $connect_portname (@table) {
					my $meter_port;
					$meter_port->{type} = "channel_in";
					$meter_port->{jack_port_name} = $connect_portname;
					$meter_port->{current_value} = 0;
					$meter_port->{current_peak} = 0;
					$meter_port->{clip_count} = 0;
					#add meter value
					push @meter_values , $meter_port;
				}
			}

			if (($mixer->{$channelname}->is_submix_in)
				or ($mixer->{$channelname}->is_main_in)
				or ($mixer->{$channelname}->is_hardware_out) ) { 

			# --- channel_out, aux_out, main_out---
				my @table = $project->{mixers}{$mixername}->get_channel_out_jackportnames($channelname);
				foreach my $connect_portname (@table) {
					my $meter_port;
					$meter_port->{type} = "channel_out" if $mixer->{$channelname}->is_main_in;
					$meter_port->{type} = "aux_out" if $mixer->{$channelname}->is_aux;
					$meter_port->{type} = "main_out" if $mixer->{$channelname}->is_main_out;
					$meter_port->{jack_port_name} = $connect_portname;
					$meter_port->{current_value} = 0;
					$meter_port->{current_peak} = 0;
					$meter_port->{clip_count} = 0;
					#add meter value
					push @meter_values , $meter_port;
				}
			}

			if ($project->{mixers}{$mixername}->is_main) {

			# --- channel_aux ---

				#ignore aux channel themselves and mainout
				next if (($mixer->{$channelname}->is_aux) or ($mixer->{$channelname}->is_main_out));

				my @table = $project->{mixers}{$mixername}->get_channel_aux_jackportnames($channelname);
				foreach my $connect_portname (@table) {
					my $meter_port;
					$meter_port->{type} = "channel_aux";
					$meter_port->{jack_port_name} = $connect_portname;
					$meter_port->{current_value} = undef;
					$meter_port->{current_peak} = undef;
					$meter_port->{clip_count} = 0;
					#add meter value
					push @meter_values , $meter_port;
				}
			}
		}
	}
	return \@meter_values;
}

sub Start {
	my $meters_hash = shift;
	return unless $meters_hash->{enable};

	if ($meters_hash->{backend} =~ "jack-peak") {
		# build the array of jack ports
		my @ports;
		push @ports , $_->{jack_port_name} for (@{$meters_hash->{values}});
		$meters_hash->{PID} = &launch_jackpeak_fifo(\@ports,$meters_hash->{port},$meters_hash->{peaks},
			$meters_hash->{speed},$meters_hash->{scale});
	}
}

sub Stop {
	my $meters_hash = shift;
	return unless $meters_hash->{enable};
	$meters_hash->stop_jackpeak_meters if ($meters_hash->{backend} =~ "jack-peak");
}

###########################################################
#
#		 meters with JACK-PEAK
#
###########################################################

sub launch_jackpeak_fifo {
	my $ports = shift; # an arrayref containing a list of ports you want to meter
	return unless $#{$ports} >= 0; # return if ports list is empty

	my $fifo = shift; # a path to the fifo to be created
	return unless $fifo; # return if fifo is empty

	my $with_peaks = shift; # logical value to create peak hold values
	my $speed = shift || "100" ; # output speed in milliseconds (default 100ms)
	my $scale = shift || "linear" ; # linear or db scale
	my $list_of_ports = join ' ' , @{$ports};
	#building command line
	my $command = "jack-peak2 -d $speed ";
	$command .= "-i 1 " if $scale eq "db";
	$command .= "-p " if $with_peaks;
	$command .=  $list_of_ports;

	#verify if another instance is running
	my $pid_jackpeak;
	my @lines = qx(ps ax | grep jack-peak2 | grep -v grep);
	if ($#lines > 0) {
		die "Error: multiple jack-peak2 instances found\n";
	}
	elsif ($#lines == -1) {
		print "jack-peak2 is not running, starting it\n";

		# create fifo if necessary
	 	unless ( -p $fifo ) {
	 		use POSIX qw(mkfifo);
			mkfifo($fifo, 0644) or die "Meters error : could not create fifo $fifo : $!\n";
			print "Meters: FIFO $fifo created\n"
		}

		#starting jack-peak
		$command .=  " > " . $fifo . " 2>/dev/null &";
		system("$command");
		sleep 2;
		#as the command line most probably contains meta characters (space escaped with \), perl starts the command in a new shell
		# so $pid_jackpeak = qx(pgrep jack-peak2); won't work as /bin/sh is the main process, so we do :
		my $ps = qx(ps ax | grep jack-peak2);
		if ($ps =~ /^(\d+?) (.*) jack-peak2/ ) {
			$pid_jackpeak = $1;
			chomp $pid_jackpeak;
		}
	 	die "Meters error: could not start jack-peak2 with command $command\n" unless $pid_jackpeak;
	}
	elsif ($#lines == 0) {
		$command =~ s/[\\]//g; #remove backslashes from command for correct comparison
		$lines[0] =~ s/[\\]//g; #remove backslashes from command for correct comparison
		if ((index($lines[0], $command) != -1) and ( $lines[0] =~ /(\d+?) / )) {
			$pid_jackpeak = $1;
			print "jack-peak2 is already running with expected parameters\n";
		}
		else {
			die "jack-peak2 doesn\'t have expected parameters,found :\n $lines[0] ----wanted :\n$command";
		}
	}
	print "jack-peak2 running with PID $pid_jackpeak\n";
	return $pid_jackpeak;
}

sub stop_jackpeak_meters {
	my $meters_hash = shift;
	return unless $meters_hash->{enable};

	# close opened handles
	close $meters_hash->{pipefh} if defined $meters_hash->{pipefh};
	undef $meters_hash->{events} if defined $meters_hash->{events};

	# kill process by PID
	if (defined $meters_hash->{PID}) {
		print "Stopping jack-peak2 with PID $meters_hash->{PID}\n";
		kill 'KILL',$meters_hash->{PID};
	}
	# or brute
	else {
		print "Force killall jack-peak\n";
		my $blob = `killall jack-peak2`;
	}
}

###########################################################
#
#		 meters with ECASOUND
#
###########################################################

sub start_ecasound_meters {
}
sub stop_ecasound_meters {
}
sub read_ecasound_meters {
}

1;
