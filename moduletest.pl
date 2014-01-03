#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

require ("modules/MidiCC.pm");
require ("modules/EcaFx.pm");

#--------essai direct avec get controls OK----------
# my ($code,$message,%truc) = EcaFx::getcontrols("eqq3b");
# if ($code eq 0) {
	# print "$message\n";
# }
# else {
	# print Dumper \%truc;
# }

#-------essai avec generate_km OK-------------
my $string = MidiCC::generate_km("eqq3b");
print "$string\n";
$string = MidiCC::generate_km("eq4b");
print "----\n";
print "$string\n";
