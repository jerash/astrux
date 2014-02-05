#!/usr/bin/perl

package NonEngine;

use strict;
use warnings;

my $debug = 0;

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

	die "Error: Mixer must exist before init\n" unless $nonengine->{status} eq "new";

	$nonengine->{files}{options} = "Settings\n\tRows\n\t\tOne\n\tLearn\n\t\tBy Strip Name";
	$nonengine->{files}{mappings} = "";
	$nonengine->{files}{info} = "created by\n\tThe Non-Mixer 1.2.0\ncreated on\n\tSun Jan 31 21:21:21 2014\nversion\n\t1";
	#update status
	$nonengine->{status} = "init";
}

###########################################################
#
#		 NONMIXER FILE functions
#
###########################################################

sub CreateNonFiles {
	# body...
}

1;
