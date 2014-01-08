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
	my @i_chaintab;
	my @o_chaintab;
	my @i_nametab;
	my @o_nametab;
	my @x_chaintab;
	foreach my $name (keys %{$mixer->{IOs}} ) {
		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = EcaStrip->new($mixer->{IOs}{$name});

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==INPUTS,RETURNS==
		if ( $strip->is_main_in) {
			#create ecasound chain
			push( @i_chaintab , $strip->create_input_chain($name) );
			push( @o_chaintab , $strip->create_loop_output_chain($name) );
			push( @i_nametab , $name );			
		}
		#==SUBMIX==
		if ($strip->is_submix_in) {

		}
		#==BUS OUTPUTS AND SEND==
		elsif ( $strip->is_hardware_out or $strip->is_submix_out) {
			push( @i_chaintab , $strip->create_bus_input_chain($name) );
			push( @o_chaintab , $strip->create_bus_output_chain($name) );
			push( @o_nametab , $name );			
		}
		#==PLAYERS==
		elsif ( $strip->is_hardware_out) {
			#connect input to null/rtnull
		}
	}
	#==CHANNELS ROUTING TO BUSES AND SENDS==
	#if we're on main mixer, create the routes to the buses
	if ($mixer->get_name eq "main") {
		my @xin = split ( "\n" , EcaStrip::create_aux_input_chains(\@i_nametab,\@o_nametab));
		my @xot = split ( "\n" , EcaStrip::create_aux_output_chains(\@i_nametab,\@o_nametab));
		push(@x_chaintab,@xin);
		push(@x_chaintab,@xot);

		#TODO : remove send to return loop
			#dans les inputs : même chaine autour de _to_ délimité avant par : ou , et après par , ou \s
			#dans les outputs : supprimer la ligne qui contient la même chaine autour de _to_
		#print Dumper @x_chaintab;
	}
	#add input chains to ecasound info
	$mixer->{ecasound}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{ecasound}{o_chains} = \@o_chaintab if @o_chaintab;
	
	#add aux chains to ecasound info
	$mixer->{ecasound}{x_chains} = \@x_chaintab if @x_chaintab;
	
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