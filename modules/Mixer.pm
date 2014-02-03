#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

use EcaEngine;
use EcaStrip;
use NonEngine;
use NonStrip;

my $debug = 0;

sub new {
	my $class = shift;
	my $ini_mixer_file = shift;
	
	my $mixer = {
		"engine" => {},
		"IOs" => {}
	};
	bless $mixer, $class;

	#if parameter exist, fill from ini file and create the mixer file
	$mixer->init($ini_mixer_file) if defined $ini_mixer_file;

	return $mixer;
}

sub init {
	my $mixer = shift;
	my $ini_mixer_file = shift;
	
	use Config::IniFiles;
	#ouverture du fichier ini de configuration des channels
	tie my %mixer_io, 'Config::IniFiles', ( -file => $ini_mixer_file );
	die "reading I/O ini file failed\n" until %mixer_io;
	my $mixer_io_ref = \%mixer_io;

	#verify in [mixer_globals] section exists
	if (!$mixer_io_ref->{mixer_globals}) {
		die "missing [mixer_globals] section in $ini_mixer_file mixer file\n";
	}

	#update mixer structure with globals
	my %globals = %{$mixer_io_ref->{mixer_globals}};
	#add global info info to mixer
	$mixer->{engine} =\%globals;
	$mixer->{engine}{status} = "notcreated";
	#remove mixer globals from IO hash to prevent further ignore
	delete $mixer_io_ref->{mixer_globals};

	#test wich engine we use
	if ($globals{engine} eq "ecasound") {
		#bless structure to access data with module functions
		bless $mixer->{engine} , EcaEngine::;
		#add ecasound header info
		$mixer->{engine}->add_header;
	}
	elsif ($globals{engine} eq "non-mixer") {
		#bless structure to access data with module functions
		bless $mixer->{engine} , NonEngine::;

		#TODO nonmixer globals
	}

	#add IO info to mixer
	$mixer->{IOs} = $mixer_io_ref;

	#add channel strips to mixer
	$mixer->CreateMainMixer if $mixer->is_main;
	$mixer->CreateSubmix if $mixer->is_submix;
	$mixer->CreatePlayers if $mixer->is_player;

	#remove IO info not necessary anymore
	delete $mixer->{IOs};
}
#--------------Create functions-------------------------
sub CreateMainMixer {
	my $mixer = shift;
	if ($mixer->is_ecasound) {
		$mixer->CreateEcaMainMixer;
	}
	elsif ($mixer->is_nonmixer) {
		$mixer->CreateNonMainMixer;
	}
}
sub CreateSubmix {
	my $mixer = shift;
	if ($mixer->is_ecasound) {
		$mixer->CreateEcaSubmix;
	}
	elsif ($mixer->is_nonmixer) {
		$mixer->CreateNonSubmix;
	}
}
sub CreatePlayers {
	my $mixer = shift;
	die "Players mixer must be ecasound !!\n" if !$mixer->is_ecasound;
	$mixer->CreateEcaPlayers;
}

#--------------Test functions-------------------------
sub is_main {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "main";
	return 0;
}
sub is_submix {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "submix";
	return 0;
}
sub is_player {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "player";
	return 0;
}
sub is_ecasound {
	my $mixer = shift;
	return 1 if $mixer->{engine}{engine} eq "ecasound";
	return 0;
}
sub is_nonmixer {
	my $mixer = shift;
	return 1 if $mixer->{engine}{engine} eq "non-mixer";
	return 0;
}

#--------------Utility functions-------------------------
sub get_name {
	my $mixer = shift;
	return $mixer->{engine}{name};
}
sub get_port {
	my $mixer = shift;
	return $mixer->{engine}{port};
}
sub is_midi_controllable {
	my $mixer = shift;
	return $mixer->{engine}{generatekm};
}

#--------------ECASOUND functions-------------------------
sub CreateEcaMainMixer {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:CreateMainMixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === I/O Channels, Buses, Sends ===
	#----------------------------------------------------------------
	my @i_chaintab;
	my @o_chaintab;
	my @i_nametab;
	my @o_nametab;
	my @x_chaintab;

	#check each channel defined in the IO
	foreach my $name (keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = EcaStrip->new($mixer->{IOs}{$name});

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==INPUTS,RETURNS,SUBMIX_IN,PLAYERS_IN==
		if ( $strip->is_main_in ) {
			#create ecasound chain
			push( @i_chaintab , $strip->create_input_chain($name) );
			push( @o_chaintab , $strip->create_loop_output_chain($name) );
			push( @i_nametab , $name );
		}
		#==BUS OUTPUTS AND SEND==
		elsif ( $strip->is_hardware_out ) {
			push( @i_chaintab , $strip->create_bus_input_chain($name) );
			push( @o_chaintab , $strip->create_bus_output_chain($name) );
			push( @o_nametab , $name );			
		}
		else {
			warn "bad IO definition in main mixer with type \n" . $strip->{type};
		}
	}

	#----------------------------------------------------------------
	#==CHANNELS ROUTING TO BUSES AND SENDS==
	#----------------------------------------------------------------

	#to each channel defined as active input
	foreach my $channel (@i_nametab ) {		

		#create aux input line
		my $iline = "-a:";

		#add a route to the defined buses
		foreach my $bus (@o_nametab) {

			if ( $mixer->{channels}{$bus}{return} and ( $mixer->{channels}{$bus}{return} eq $channel )) {
				print "   |_info: discarding sendbus to himself ($bus) \n";
			}
			else {
				
				#init the aux input line
				$iline .= "$channel" . "_to_$bus,";

				#create a channel strip
				my $strip = EcaStrip->new;
	
				#verify if the channel is defined using midi control
				my $km = $mixer->{channels}{$channel}{generatekm};
	
				#init the aux strip
				$strip->aux_init($km);
	
				#add aux route strip to mixer
				$mixer->{channels}{$channel}{aux_route}{$bus} = $strip;

				#grab the aux route inserts (static define to panvol only)
				my $inserts = $mixer->{channels}{$channel}{aux_route}{$bus}{inserts}{panvol}{ecsline};
				#create aux outputs line
				my $oline = "-a:" . $channel . "_to_$bus -f:f32_le,2,48000 -o:jack,,to_bus_$bus $inserts";
				push  (@x_chaintab , $oline );
			}
		}

		#finish the aux input line
		chop($iline);
		$iline .= " -f:f32_le,2,48000 -i:loop,$channel";
		push  (@x_chaintab , $iline );
	}

	#add aux chains to ecasound info
	$mixer->{engine}{x_chains} = \@x_chaintab if @x_chaintab;

	#add input chains to ecasound info
	$mixer->{engine}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{engine}{o_chains} = \@o_chaintab if @o_chaintab;

	#udpate mixer info with curretly selected chainsetup
	$mixer->{current}{chainsetup} = $mixer->{engine}->get_selected_chainsetup;
	#udpate mixer info with curretly selected chain (channel)
	$mixer->{current}{channel} = $mixer->{engine}->get_selected_channel;
	#udpate mixer info with curretly selected effect
	$mixer->{current}{effect} = $mixer->{engine}->get_selected_effect;

}

sub CreateEcaSubmix {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:Create Submix mixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === Submix ===
	#----------------------------------------------------------------

	my @i_chaintab;
	my @o_chaintab;

	#check each channel defined in the IO
	foreach my $name (keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = EcaStrip->new($mixer->{IOs}{$name});

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==SUBMIX==
		#create ecasound chain
		push( @i_chaintab , $strip->create_input_chain($name) ) if ( $strip->is_submix_in );
		push( @o_chaintab , $strip->create_submix_output_chain($name) ) if ( $strip->is_submix_out );
		warn "bad IO definition in submix with type \n" . $strip->{type} unless ( ( $strip->is_submix_in ) or ( $strip->is_submix_out ));
	}

	#add input chains to ecasound info
	$mixer->{engine}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{engine}{o_chains} = \@o_chaintab if @o_chaintab;

}

sub CreateEcaPlayers {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:Create Player mixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === Players ===
	#----------------------------------------------------------------

	my @io_chaintab;

	#check each channel defined in the IO
	foreach my $name (keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = EcaStrip->new($mixer->{IOs}{$name});

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==PLAYERS==
		#create ecasound chain
		push( @io_chaintab , $strip->create_player_chain($name) ) if ( $strip->is_file_player );
		warn "bad IO definition in players with type \n" . $strip->{type} unless ( $strip->is_file_player );
	}

	#add chains to ecasound info
	$mixer->{engine}{io_chains} = \@io_chaintab if @io_chaintab;
}

#-------------- NON-MIXER functions -------------------------

sub CreateNonMainMixer {
	# body...
}
sub CreateNonSubmix {
	# body...
}

1;