#!/usr/bin/perl

package EcaStrip;

use strict;
use warnings;
use EcaFx;

use Data::Dumper;

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

	#update channel strip info from ini
	$ecastrip->{friendly_name} = $IOsection->{friendly_name};
	$ecastrip->{status} = $IOsection->{status};
	$ecastrip->{can_be_backed} = $IOsection->{can_be_backed};
	$ecastrip->{group} = $IOsection->{group};
	$ecastrip->{type} = $IOsection->{type};
	$ecastrip->{generatekm} = $IOsection->{generatekm};

	#deal with each channel type
	if ($ecastrip->{type} eq "file_in") {
		#these infos depend on song content
		$ecastrip->{channels} = undef;
		$ecastrip->{connect} = undef;
	}
	else {
		$ecastrip->{channels} = $IOsection->{channels};	
		#en fonction du nombre de channels on crée une liste des inputs
		my @tab;
		$ecastrip->{mode} = $IOsection->{mode} if defined $IOsection->{mode};
		#mono channel
		if (defined $IOsection->{mode} and $IOsection->{mode} eq "mono") {
			#get connect port
			push ( @tab , $IOsection->{"connect_1"});
		}
		#stereo channel or more
		else {
			#get connect port
			push ( @tab , $IOsection->{"connect_$_"}) for (1 .. $IOsection->{channels});
		}
		$ecastrip->{connect} = \@tab;
	}

	#verify if we generate km controllers (midi)
	my $km = $ecastrip->{generatekm};

	#add pan and volume controls
	if ($ecastrip->is_mono) {
			$ecastrip->{inserts}{panvol} = EcaFx->new("mono_panvol",$km);
	}
	elsif ($ecastrip->is_stereo) {
		$ecastrip->{inserts}{panvol} = EcaFx->new("st_panvol",$km);
	}

	#get list of inserts
	my @effects = split ',',$IOsection->{insert} if $IOsection->{insert};	
	
	#add inserts
	foreach my $effect (@effects) {
		$ecastrip->{inserts}{$effect} = EcaFx->new($effect,$km);
	}	
}

sub create_input_chain {
	my $strip = shift;
	my $name = shift;

	die "must have a track name\n" if $name eq "";

	my $line = "-a:$name ";
	$line .= "-f:f32_le,1,48000 -i:jack,," if $strip->is_mono;
	$line .= "-f:f32_le,2,48000 -i:jack,," if $strip->is_stereo;
	$line .= $name;
	return $line;
}
sub create_output_chain {
	my $strip = shift;
	my $name = shift;

	die "must have a track name\n" if $name eq "";

	return "-a:$name -f:f32_le,2,48000 -o:loop,$name";
}

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
sub is_player_track {
	my $io = shift;
	return 1 if ($io->{type} eq "player");
	return 0;
}
sub is_player {
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
	return 1 if ($io->{channels} eq "1");
	return 0;	
}
sub is_stereo {
	my $io = shift;
	return 1 if ($io->{channels} eq "2");
	return 0;	
}
sub is_summed_mono {
	#applicable to outputs only
	my $io = shift;
	return 1 if (($io->{channels} eq "2")and($io->{mode} eq "mono"));
	return 0;	
}
1;