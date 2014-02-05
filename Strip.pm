#!/usr/bin/perl

package Strip;

use strict;
use warnings;
use Data::Dumper;

use Fx;

###########################################################
#
#		 STRIP OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $IOsection = shift;

	#init structure
	my $strip = {
		'friendly_name' => "",
		'status' => "new",
		'can_be_backed' => "",
		'type' => "",
		'inserts' => {},
		'channels' => "",
		'connect' => "",
		'group' => ""
	};
	bless $strip, $class;
	
	return $strip;
}

sub init {
	#fill the strip object with the passed hash info
	my $strip = shift;
	my $IOsection = shift;
	my $midi_km = shift;
	
	die "Error: can't init a strip without info\n" unless defined $IOsection;
	warn "Warning: undefined value on midi option\n" unless defined $midi_km;

	#don't insert channel if inactive
	return unless $IOsection->{status} eq "active";

	#update channel strip info from ini
	$strip->{friendly_name} = $IOsection->{friendly_name} if $IOsection->{friendly_name};
	$strip->{status} = $IOsection->{status} if $IOsection->{status};
	$strip->{can_be_backed} = $IOsection->{can_be_backed} if $IOsection->{can_be_backed};
	$strip->{group} = $IOsection->{group} if $IOsection->{group};
	$strip->{type} = $IOsection->{type} if $IOsection->{type};
	$strip->{return} = $IOsection->{return} if $IOsection->{return};
	$strip->{channels} = $IOsection->{channels} if $IOsection->{channels};
	$strip->{mode} = $IOsection->{mode} if defined $IOsection->{mode};
	
	print "   |_adding channel ".$strip->{friendly_name}."\n";
	
	#en fonction du nombre de channels on crée une liste des inputs
	my @tab;

	#mono channel >> to be used on output buses to save hardware channels if needed
	if (defined $IOsection->{mode} and $IOsection->{mode} eq "mono") {
		#get connect port
		push ( @tab , $IOsection->{"connect_1"});
	}
	#stereo channel or more
	else {
		#get connect port
		push ( @tab , $IOsection->{"connect_$_"}) for (1 .. $IOsection->{channels});
	}

	#add the connect channel to structure
	$strip->{connect} = \@tab;
	
	#get list of inserts
	my @effects = split ',',$IOsection->{insert} if $IOsection->{insert};	
	
	#add inserts
	my $sequence_nb = 1;
	foreach my $effect (@effects) {
		die "Can't have more than 20 inserts on a track\n" if ($sequence_nb eq 21);

		#verify if we want to add pan and volume
		if ( $effect eq "panvol" ) {
			#add pan and volume controls, applicable to ecasound engine only
			if ($strip->is_mono) {
					$strip->{inserts}{panvol} = Fx->new("mono_panvol",$midi_km);
			}
			elsif ($strip->is_stereo) {
				$strip->{inserts}{panvol} = Fx->new("st_panvol",$midi_km);
			}
		}
		else{
			$strip->{inserts}{$effect} = Fx->new($effect,$midi_km);
		}
		
		#give an sequence number to the plugin
		$strip->{inserts}{$effect}{nb} = $sequence_nb;
		$sequence_nb++;
	}	
}

###########################################################
#
#			ECASOUND functions
#
###########################################################
sub eca_aux_init {
	my $strip = shift;
	my $midi_km = shift;

	#init values
	$strip->{type} = "route";
	$strip->{channels} = "2";
	delete $strip->{group};
	delete $strip->{status};
	delete $strip->{connect};
	delete $strip->{friendly_name};
	delete $strip->{can_be_backed};

	#add pan and volume
	$strip->{inserts}{panvol} = Fx->new("st_panvol",$midi_km);
}

sub get_eca_chain_add_inserts {
	my $strip = shift;
	my $line;

	#get a list of inserts
	my @inserts = keys %{$strip->{inserts}};

	#return empty line if there is no effects (should never be as panvol is added)
	return '' unless @inserts;

	#make sure to add effects with the correct order
	for my $i (1..$#inserts+1) {
		for my $nb (0..$#inserts){
			my $insertname = $inserts[$nb];
			next if $strip->{inserts}{$insertname}{nb} ne $i;
			#when we found the good one, create line
			my $insert = $inserts[$nb];
			print "   | |_adding effect $insert\n";
			$line .= $strip->{inserts}{$insert}{ecsline} if (defined $strip->{inserts}{$insert}{ecsline});
		}
	}
	return $line;	
}

sub get_eca_input_chain {
	my $strip = shift;
	my $name = shift;

	my $line = "-a:$name ";
	$line .= "-f:f32_le,1,48000 -i:jack,," if $strip->is_mono;
	$line .= "-f:f32_le,2,48000 -i:jack,," if $strip->is_stereo;
	$line .= $name;
	#add inserts if any
	$line .= $strip->get_eca_chain_add_inserts();
	return $line;
}
sub get_eca_loop_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:$name -f:f32_le,2,48000 -o:loop,$name";
}

sub get_eca_bus_input_chain {
	my $strip = shift;
	my $name = shift;
	my $inserts = $strip->get_eca_chain_add_inserts();
	return "-a:bus_$name -f:f32_le,2,48000 -i:jack,,bus_$name $inserts";
}
sub get_eca_bus_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:bus_$name -f:f32_le,2,48000 -o:jack,,$name";
}

sub get_eca_player_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:$name -f:f32_le,2,48000 -i:null -o:jack,,$name";
}

sub get_eca_submix_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:all -f:f32_le,2,48000 -o:jack,,$name";
}

###########################################################
#
#		 NON-MIXER functions
#
###########################################################
sub get_non_input_chain {
	# body...
}
sub get_non_bus_input_chain {
	# body...
}

###########################################################
#
#		 GLOBAL TEST functions
#
###########################################################

sub is_active{
	my $io = shift;
	return 1 if ($io->{status} eq "active");
	return 0 if ($io->{status} eq "inactive");
	return 0 if ($io->{status} eq "new");
}

sub is_main_in {
	my $io = shift;
	return 1 if (($io->{type} eq "hardware_in") or
				 ($io->{type} eq "return") or
				 ($io->{type} eq "player") or
				 ($io->{type} eq "submix"));
	return 0;	
}
sub is_hardware_out {
	my $io = shift;
	return 1 if (($io->{type} eq "bus_hardware_out") or
				 ($io->{type} eq "main_hardware_out") or
				 ($io->{type} eq "send_hardware_out"));
	return 0;	
}
sub is_hardware_in {
	my $io = shift;
	return 1 if ($io->{type} eq "hardware_in");
	return 0;
}

sub is_bus_in {
	my $io = shift;
	return 1 if ($io->{type} eq "player");
	return 1 if ($io->{type} eq "submix");
	return 0;
}
sub is_bus_out {
	my $io = shift;
	return 1 if ($io->{type} eq "bus_hardware_out");
	return 0;
}
sub is_main_out {
	my $io = shift;
	return 1 if ($io->{type} eq "main_hardware_out");
	return 0;
}
sub is_aux {
	my $io = shift;
	return 1 if ($io->{type} eq "send_hardware_out");
	return 1 if ($io->{type} eq "bus_hardware_out");
	return 0;
}
sub is_send {
	my $io = shift;
	return 1 if ($io->{type} eq "send_hardware_out");
	return 0;
}
sub is_return {
	my $io = shift;
	return 1 if ($io->{type} eq "return");
	return 0;
}

sub is_submix_in {
	my $io = shift;
	return 1 if ($io->{type} eq "audio_in");
	return 0;
}
sub is_submix_out {
	my $io = shift;
	return 1 if ($io->{type} eq "audio_out");
	return 0;
}

sub is_audio_player_track {
	my $io = shift;
	return 1 if ($io->{type} eq "audio_player");
	return 0;
}
sub is_file_player {
	my $io = shift;
	return 1 if ($io->{type} eq "file_in");
	return 0;
}

sub is_submix {
	my $io = shift;
	return 1 if ($io->{type} eq "submix");
	return 0;
}

sub is_mono {
	my $io = shift;
	if ($io->{channels}) {
		return 1 if ($io->{channels} eq "1");
	}
	return 0;	
}
sub is_stereo {
	my $io = shift;
	if ($io->{channels}) {
		return 1 if ($io->{channels} eq "2");
	}
	return 0;	
}
sub is_summed_mono {
	#applicable to outputs only
	my $io = shift;
	return 1 if (($io->{channels} eq "2")and($io->{mode} eq "mono"));
	return 0;	
}

1;