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
#		{options}
#			backend
#			port
#			PID
#		@{values}
#			{jack_port_name}
# 				current_value	[0..1]
# 				current_peak	[0..1]
# 				clip_count 		(may be used as accumulator to trigger clip led if > 3)

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
	my $meters = {
		"options" => $options
	};
	bless $meters,$class;

	return $meters; 
}

###########################################################
#
#		 METERS functions
#
###########################################################

sub create_meters {
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
					$meter_port->{current_value} = 0;
					$meter_port->{current_peak} = 0;
					$meter_port->{clip_count} = 0;
					#add meter value
					push @meter_values , $meter_port;
				}
			}
		}
	}
	return \@meter_values;
}

###########################################################
#
#		 meters with JACK-PEAK
#
###########################################################

sub start_jackpeak_meters {
	my $ports = shift; # an arrayref containing a list of ports you want to meter
	return unless $#{$ports} >= 0; # return if ports list is empty

	my $fifo = shift; # a path to the fifo to be created
	return unless $fifo; # return if fifo is empty

	my $with_peaks = shift; # logical value to create peak hold values

 	unless ( -p $fifo ) {
 		use POSIX qw(mkfifo);
		mkfifo($fifo, 0644) or die "Meters error : could not create fifo $fifo : $!\n";
		print "Meters: FIFO $fifo created\n"
	}
	my $list_of_ports = join ' ' , @{$ports};
	my $command = "jack-peak2 " . $list_of_ports;
	$command .= " -p" if $with_peaks;
	$command .= " > " . $fifo . " 2>/dev/null &";

	# TODO fork&exec to get pid so we can stop it later
	# TODO check return code / error messages
	system($command);
}

sub stop_jackpeak_meters {
	# by PID or by fifo(port)
}

use Fcntl;
sub read_jackpeak_meters {
	my $fifofile = shift;
	return unless $fifofile;
	$| = 1;
	my $fifo_fh;
	# open in non-blocking mode if nothing is to be read in the fifo
	sysopen($fifo_fh, $fifofile, O_RDWR) or warn "The FIFO file \"$fifofile\" is missing\n";
	while (<$fifo_fh>) { return "$_";};
	#we'll never reach here unless the fifo is empty
	close $fifo_fh;
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
