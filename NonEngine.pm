#!/usr/bin/perl

package NonEngine;

use strict;
use warnings;

my $debug = 1;

###########################################################
#
#		 NONMIXER OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $output_path = shift;
	my $enginename = shift;
	die "EcaEngine Error: can't create ecs engine without a path\n" unless $output_path;
	die "EcaEngine Error: can't create ecs engine without a name\n" unless $enginename;

	my $nonengine = {
		"path" => $output_path,
		"name" => $enginename
	};
	bless $nonengine, $class;

	#update engine status
	$nonengine->{status} = "new";

	#init engine
	$nonengine->init;

	return $nonengine;
}

sub init {
	my $nonengine = shift;

	die "Error: Mixer must exist before init\n" unless $nonengine->{status} eq "new"||"init";

	$nonengine->{files}{options} = "Settings\n\tRows\n\t\tOne\n\tLearn\n\t\tBy Strip Name";
	$nonengine->{files}{mappings} = "";
	$nonengine->{files}{info} = "created by\n\tThe Non-Mixer 1.2.0\ncreated on\n\tSun Jan 31 21:21:21 2014\nversion\n\t1";
	#update status
	$nonengine->{status} = "init";
}

###########################################################
#
#		 NONMIXER functions
#
###########################################################

sub StartNonmixer {
	my $nonengine = shift;

	my $path = $nonengine->{path} . "/" . $nonengine->{name};
	my $port = $nonengine->{osc_port};
	my $name = $nonengine->{name};
	
	#if mixer is already running on same port, then reconfigure it
	if  ($nonengine->is_running) {
		print "    Found existing Nonmixer engine on osc port $port, reconfiguring engine\n";
		#TODO how to say nomixer to load a new project ? osc...nsm...
		print "\n ...well one day we willl do it, not ready \n";
	}
	#if mixer is not existing, launch mixer with needed file
	else {
		# my $command = "non-mixer-noui $path --instance $name --osc-port $port > /dev/null 2>&1 &\n";
		my $command = "non-mixer-noui $path --instance $name --osc-port $port &\n";
		system ( $command );
		#wait for mixer to be ready
		# TODO sleep(1) until $nonengine->is_ready;
		print "   Nonmixer $nonengine->{name} is ready\n";
	}
}

###########################################################
#
#		 NONMIXER STATUS functions
#
###########################################################

sub is_ready {
	my $nonengine = shift;

	#return 1 if 1; #TODO send osc ping and read pong
	
	#check for PID in case it can't start so we don't wait undefinately

	return 0;
}
sub is_running {
	my $nonengine = shift;

	my $port = $nonengine->{osc_port};
	my $name = $nonengine->{name};

	my $ps = qx(ps ax);
	# print "***\n $ps \n***\n";
	($ps =~ /non-mixer/ and $ps =~ /--instance $name/ and $ps =~ /osc-port=$port/) ? return 1 : return 0;
}

###########################################################
#
#		 NONMIXER FILE functions
#
###########################################################



1;
