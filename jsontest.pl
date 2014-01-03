#!/usr/bin/perl
use strict;
use warnings;
use JSON::XS;
use Data::Dumper;

my %h =( "daddy", '0' , "mummy" , '1' , "freggy" , {"bli","err","bla","or"} );

print Dumper \%h;

my $text = encode_json(\%h);

print $text;