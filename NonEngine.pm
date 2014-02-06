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

	my $nonengine = {};
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
	print "Wohoho soon we'll start non mixer!!\n";
}

###########################################################
#
#		 NONMIXER STATUS functions
#
###########################################################

sub is_ready {
	my $nonengine = shift;

	return 1 if 1; #TODO send osc ping and read pong
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
