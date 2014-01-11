#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

use Config::IniFiles;
use EcaFile;
use EcaStrip;

use Data::Dumper;

sub new {
	my $class = shift;
	my $ini_mixer_file = shift;
	
	my $mixer = {
		"ecasound" => {},
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
	#add ecasound info to mixer
	$mixer->{ecasound} =\%globals;
	$mixer->{ecasound}{status} = "notcreated";
	#remove mixer globals from IO hash to prevent further ignore
	delete $mixer_io_ref->{mixer_globals};

	#add IO info to mixer
	$mixer->{IOs} = $mixer_io_ref;

	#add ecasound header info
	$mixer->add_header;
	#add channel strips to mixer
	$mixer->CreateMainMixer if $mixer->is_main;
	$mixer->CreateSubmix if $mixer->is_submix;
	$mixer->CreatePlayers if $mixer->is_player;

	#remove IO info not necessary anymore
	delete $mixer->{IOs};
}
sub add_header {
	my $mixer = shift;

	my $name = $mixer->{ecasound}{name};
	my $header = "#GENERAL\n";
	$header .= "-b:".$mixer->{ecasound}{buffersize} if $mixer->{ecasound}{buffersize};
	$header .= " -r:".$mixer->{ecasound}{realtime} if $mixer->{ecasound}{realtime};
	my @zoptions = split(",",$mixer->{ecasound}{z});
	foreach (@zoptions) {
		$header .= " -z:".$_;
	}
	$header .= " -n:\"$name\"";
	$header .= " -z:mixmode,".$mixer->{ecasound}{mixmode} if $mixer->{ecasound}{mixmode};
	$header .= " -G:jack,$name,notransport" if ($mixer->{ecasound}{sync} == 0);
	$header .= " -G:jack,$name,sendrecv" if ($mixer->{ecasound}{sync});
	$header .= " -Md:".$mixer->{ecasound}{midi} if $mixer->{ecasound}{midi};
	#add to tructure
	$mixer->{ecasound}{header} = $header;
	#update status
	$mixer->{ecasound}{status} = "header";
}


sub CreateMainMixer {
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

	#==CHANNELS ROUTING TO BUSES AND SENDS==
	my @xin = split ( "\n" , EcaStrip::create_aux_input_chains(\@i_nametab,\@o_nametab,$mixer));
	my @xot = split ( "\n" , EcaStrip::create_aux_output_chains(\@i_nametab,\@o_nametab,$mixer));
	push(@x_chaintab,@xin);
	push(@x_chaintab,@xot);

	#add aux chains to ecasound info
	$mixer->{ecasound}{x_chains} = \@x_chaintab if @x_chaintab;

	#add input chains to ecasound info
	$mixer->{ecasound}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{ecasound}{o_chains} = \@o_chaintab if @o_chaintab;
}

sub CreateSubmix {
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
	$mixer->{ecasound}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{ecasound}{o_chains} = \@o_chaintab if @o_chaintab;

}

sub CreatePlayers {
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
	$mixer->{ecasound}{io_chains} = \@io_chaintab if @io_chaintab;
}

sub get_ecasoundchains {
	my $mixer = shift;

	#option to cleanup strucutre by removing io chains after compiling to all_chains
	my $remove = 1;

	my @table;

	if (defined $mixer->{ecasound}{i_chains}) {
		push @table , "\n#INPUTS\n";
		push @table , @{$mixer->{ecasound}{i_chains}};
		delete $mixer->{ecasound}{i_chains} if $remove;
	}
	if (defined $mixer->{ecasound}{o_chains}) {
		push @table , "\n#OUTPUTS\n";
		push @table , @{$mixer->{ecasound}{o_chains}};
		delete $mixer->{ecasound}{o_chains} if $remove;
	}
	if (defined $mixer->{ecasound}{x_chains}) {
		push @table , "\n#CHANNELS ROUTING\n";
		push @table , @{$mixer->{ecasound}{x_chains}};
		delete $mixer->{ecasound}{x_chains} if $remove;
	}
	if (defined $mixer->{ecasound}{io_chains}) {
		push @table , "\n#PLAYERS\n";
		push @table , @{$mixer->{ecasound}{io_chains}};
		delete $mixer->{ecasound}{io_chains} if $remove;
	}

	#update structure
	@{$mixer->{ecasound}{all_chains}} = @table;
	# remove unneeded lines?
	#print Dumper $mixer->{ecasound}{all_chains};
}
#--------------Test functions-------------------------
sub is_main {
	my $mixer = shift;
	return 1 if $mixer->{ecasound}{type} eq "main";
	return 0;
}
sub is_submix {
	my $mixer = shift;
	return 1 if $mixer->{ecasound}{type} eq "submix";
	return 0;
}
sub is_player {
	my $mixer = shift;
	return 1 if $mixer->{ecasound}{type} eq "player";
	return 0;
}

#--------------Utility functions-------------------------
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