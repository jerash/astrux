#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

use Config::IniFiles;
use EcaEcs;
use EcaStrip;

use Data::Dumper;

sub new {
	my $class = shift;
	my $ini_mixer = shift;
	my $ecs_file = shift;

	my $mixer = {
		"ecasound" => {},
		"IOs" => {}
	};
	bless $mixer, $class;
	#if parameter exist, fill from ini file and create the mixer file
	$mixer->init($ini_mixer,$ecs_file) if defined $ini_mixer;

	return $mixer;
}

sub init {
	my $mixer = shift;
	my $ini_mixer = shift;
	my $ecs_file = shift;

	#ouverture du fichier ini de configuration des channels
	tie my %mixer_io, 'Config::IniFiles', ( -file => $ini_mixer->{inifile} );
	die "reading I/O ini file failed\n" until %mixer_io;

	#add ecasound info to mixer
	$mixer->{ecasound} = EcaEcs->new($ini_mixer,$ecs_file);

	#add IO info to mixer
	$mixer->{IOs} = \%mixer_io;

	#add channel strips to mixer
	$mixer->CreateChannels;
}

sub CreateChannels {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print "-Mixer:CreateChannels for : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === I/O Channels, Buses, Sends ===
	#----------------------------------------------------------------
	my @i_tab;
	my @o_tab;
	foreach my $name (keys %{$mixer->{IOs}} ) {
		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

	
		#create the channel strip
		my $strip = EcaStrip->new($mixer->{IOs}{$name});

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==INPUTS,RETURNS,SUBMIXES,PLAYERS==
		if (  $strip->is_main_in) {
			#create ecasound chain
			push( @i_tab , $strip->create_input_chain($name) );
			push( @o_tab , $strip->create_output_chain($name) );
			#$mixer->{ecasound}->create_input_chain($ecs_file,$mixer->{channels});
#$ecastrip->{inserts} = $IOsection->{inserts};	
# my @tab;
# push(@tab,EcaEcs::create_input_chain($strip,$name,$km));
# $mixer->{ecasound}{i_chains} = \@tab if @tab;
		}
		#==BUS OUTPUTS AND SENS==
		elsif ( $strip->is_hardware_out) {
			print $strip->{friendly_name} . " is case2\n";
		}
	}
	#add input chains to ecasound info
	$mixer->{ecasound}{i_chains} = \@i_tab if @i_tab;
	#add output chains to ecasound info
	$mixer->{ecasound}{o_chains} = \@o_tab if @o_tab;
	#==CHANNELS ROUTING TO BUSES AND SENDS==
}

sub get_name {
	my $mixer = shift;
	return $mixer->{ecasound}{name};
}
sub get_port {
	my $mixer = shift;
	return $mixer->{ecasound}{port};
}
sub is_midi_controllable {
	my $mixer = shift;
	return $mixer->{ecasound}{generatekm};
}

1;