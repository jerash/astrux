#!/usr/bin/perl

package Load;

use strict;
use warnings;


use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw($project);

use Storable;

our $project;

sub LoadStoredProject {
	my $infile = shift;
	$project = retrieve($infile);
 	die "Could not load file $infile\n" unless $project;
}

1;