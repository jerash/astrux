#!/usr/bin/perl

package EcaStrip;

use strict;
use warnings;
use Data::Dumper;

use EcaFx;

sub new {
	my $class = shift;
	my $IOsection = shift;

	#init structure
	my $ecastrip = {
		'friendly_name' => "",
		'status' => "new",
		'can_be_backed' => "",
		'type' => "",
		'inserts' => {},
		'channels' => "",
		'connect' => "",
		'group' => ""
	};
	bless $ecastrip, $class;
	
	#if parameter exist, fill hash
	$ecastrip->init($IOsection) if defined $IOsection;
	
	return $ecastrip;
}

sub init {
	#fill the strip object with the passed hash info
	my $ecastrip = shift;
	my $IOsection = shift;
	return unless defined $IOsection;
	#don't insert channel if inactive
	return unless $IOsection->{status} eq "active";

	#update channel strip info from ini
	$ecastrip->{friendly_name} = $IOsection->{friendly_name} if $IOsection->{friendly_name};
	$ecastrip->{status} = $IOsection->{status} if $IOsection->{status};
	$ecastrip->{can_be_backed} = $IOsection->{can_be_backed} if $IOsection->{can_be_backed};
	$ecastrip->{group} = $IOsection->{group} if $IOsection->{group};
	$ecastrip->{type} = $IOsection->{type} if $IOsection->{type};
	$ecastrip->{generatekm} = $IOsection->{generatekm} if $IOsection->{generatekm};
	$ecastrip->{return} = $IOsection->{return} if $IOsection->{return};
	$ecastrip->{channels} = $IOsection->{channels} if $IOsection->{channels};
	
	print "   |_adding channel ".$ecastrip->{friendly_name}."\n";
	
	#en fonction du nombre de channels on crée une liste des inputs
	my @tab;
	$ecastrip->{mode} = $IOsection->{mode} if defined $IOsection->{mode};

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
	$ecastrip->{connect} = \@tab;
	
	#verify if we generate km controllers (midi)
	my $km = $ecastrip->{generatekm};

	#get list of inserts
	my @effects = split ',',$IOsection->{insert} if $IOsection->{insert};	
	
	#add inserts
	my $order = 0;
	foreach my $effect (@effects) {
		die "Can't have more than 20 inserts on a track\n" if ($order eq 21);
		$ecastrip->{inserts}{$effect} = EcaFx->new($effect,$km);
		$ecastrip->{inserts}{$effect}{nb} = $order;
		$order++;
	}	

	#verify to which channel to add pan and volume
	if ( !$ecastrip->is_submix_out ) {
		#add pan and volume controls
		if ($ecastrip->is_mono) {
				$ecastrip->{inserts}{panvol} = EcaFx->new("mono_panvol",$km);
		}
		elsif ($ecastrip->is_stereo) {
			$ecastrip->{inserts}{panvol} = EcaFx->new("st_panvol",$km);
		}
		#give panvol the last nb to place it at the end of insert chains
		$ecastrip->{inserts}{panvol}{nb} = "99";
	}

}

sub aux_init {
	my $strip = shift;
	my $km = shift;

	#init values
	$strip->{type} = "route";
	$strip->{channels} = "2"; 
	delete $strip->{group}; 
	delete $strip->{status}; 
	delete $strip->{connect}; 
	delete $strip->{friendly_name}; 
	delete $strip->{can_be_backed}; 

	#add pan and volume
	$strip->{inserts}{panvol} = EcaFx->new("st_panvol",$km);
}

#-------------------------------------------------------------------
#	ecasound chain management
sub create_chain_add_inserts {
	my $strip = shift;
	my $line;
	#TODO : respect an order to inserts !!! or sort is enough ?
	foreach my $insert (sort keys %{$strip->{inserts}}){
		$line .= $strip->{inserts}{$insert}{ecsline} if (defined $strip->{inserts}{$insert}{ecsline});
	}
	return $line;	
}

sub create_input_chain {
	my $strip = shift;
	my $name = shift;

	my $line = "-a:$name ";
	$line .= "-f:f32_le,1,48000 -i:jack,," if $strip->is_mono;
	$line .= "-f:f32_le,2,48000 -i:jack,," if $strip->is_stereo;
	$line .= $name;
	#add inserts if any
	$line .= $strip->create_chain_add_inserts();
	return $line;
}
sub create_loop_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:$name -f:f32_le,2,48000 -o:loop,$name";
}

sub create_bus_input_chain {
	my $strip = shift;
	my $name = shift;
	my $inserts = $strip->create_chain_add_inserts();
	return "-a:bus_$name -f:f32_le,2,48000 -i:jack,,bus_$name $inserts";
}
sub create_bus_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:bus_$name -f:f32_le,2,48000 -o:jack,,$name";
}

sub create_player_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:$name -f:f32_le,2,48000 -i:null -o:jack,,$name";
}

sub create_submix_output_chain {
	my $strip = shift;
	my $name = shift;

	return "-a:all -f:f32_le,2,48000 -o:jack,,sub_$name";
}

#-------------------------------------------------------------------
# test functions

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

sub is_player_track {
	my $io = shift;
	return 1 if ($io->{type} eq "player");
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