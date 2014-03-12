#!/usr/bin/perl

package Meters;

use strict;
use warnings;

# From jack, we're able to have meters for :
#-------------------------------------------
# INPUTS
#	channel_in (from hardware_input)
#	players_out
#	submix_out
# OUTPUTS
#	monitor_out (aux out to hardware out port)
#	send_out (aux out to hardware out port)
#	main_out (main out to hardware out port)
# ROUTINGS
#	channel_out (non-mixer channel to main out)
#	channel_aux (non-mixer channel to aux monitor)
#	submix_channel_out (nonmixer submix channel to submix out)

# Meters project structure
#-------------------------------------------
# {project_root}
#	{meters}
#		{options}
#			backend
#			port
#			PID
#		{values}
#		 	{jack_port_name}	< TODO in project channel strip add meter_ref pointing here
# 				channel_path	/main/mic_1/
# 				current_value	[0..1]
# 				current_peak	[0..1]
# 				clip_count 		(may be used as accumulator to trigger clip led if > 3)

# Corresponding osc paths 
#-------------------------------------------
# /mixer/channel/_in_meter_						(channel_in,players_out,submix_out,monitor_out,send_out,main_out,submix_channel_out)
# /mixer/channel/_in_peak_
# /mixer/channel/_in_clip_
# /mixer/channel/_out_meter_					(channel_out)
# /mixer/channel/_out_peak_
# /mixer/channel/_out_clip_
# /mixer/channel/aux_to/auxname/_send_meter_			(channel_aux)
# /mixer/channel/aux_to/auxname/_send_peak_
# /mixer/channel/aux_to/auxname/_send_clip_

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
