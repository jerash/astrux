#!/usr/bin/perl

package EcaStrip;

use strict;
use warnings;
use EcaFx;

sub new {
	my $class = shift;
	my $IOsection = shift;

	#init structure
	my $ecastrip = {
		'friendly_name' => "",
		'status' => "new",
		'can_be_backed' => "",
		'group' => "",
		'type' => "",
		'channels' => "",
		'connect' => (),
		'inserts' => (),
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
	$ecastrip->{friendly_name} = $IOsection->{friendly_name};
	$ecastrip->{status} = $IOsection->{status};
	$ecastrip->{can_be_backed} = $IOsection->{can_be_backed};
	$ecastrip->{group} = $IOsection->{group};

	$ecastrip->{type} = $IOsection->{type};
	#deal with particular cases
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
		if (defined $IOsection->{mode} and $IOsection->{mode} eq "mono") {
			push ( @tab , $IOsection->{"connect_1"});
		}
		else {
			push ( @tab , $IOsection->{"connect_$_"}) for (1 .. $IOsection->{channels});
		}
		$ecastrip->{connect} = \@tab;
	}

	#add inserts
	#TODO
	$ecastrip->{inserts} = $IOsection->{inserts};	
}

sub is_active{
	my $io = shift;
	return 1 if ($io->{status} eq "active");
	return 0 if ($io->{status} eq "inactive");
	return 0 if ($io->{status} eq "new");
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
sub is_player {
	my $io = shift;
	return 1 if ($io->{type} eq "player");
	return 1 if ($io->{type} eq "file_in");
	return 0;
}
sub is_submix {
	my $io = shift;
	return 1 if ($io->{type} eq "submix");
	return 0;
}
1;