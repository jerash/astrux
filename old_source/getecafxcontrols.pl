#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#------------------------------------------------------------------------------------------
# get the options assignables to midi from a defined effect in effect_preset ecasoudn file
# it allows midi assignation of effects defined for that project only .sic.
#
# taken as a prerequisite : 
#	plugin name must be on line start (first character)
#	pn; ppu, ppl ..etc definitions are on different lines separated by \
#
#------------------------------------------------------------------------------------------
my $debug = 0;

#check for existing single argument
die "usage : getecafxcontrols \“pluginname\" \n" until $#ARGV eq 0; 

#name of plugin passed as argument (may be incomplete)
my $plugin = $ARGV[0];

#open effect file
open(my $file, "<", "effect_presets")
	or die "cannot open < effect_presets: $!";

#get the effect parameters string
my $found =0;
my $tic = 0;
my $string = '';
while (<$file>) {
	if ( $tic == 1 ) {
		$string = $string . $_; #print $string,"\n";
		last if $_ !~ /\\$/; #print "notlast\n";
	}
	if (( /^$plugin\b/ ) && ( $tic eq 0) ) {
		$found = 1; #print "found : ",$_,"\n";
		$tic = 1 if $_ =~ /\\$/; #print "tic=",$tic,"\n";
		$string = $_;
	}
}
die "Plugin $plugin not found\n" if ($found eq 0);
#close file
close($file) || warn "close failed: $!";

my $paramnames = '';
my $defaultvalues = '';
my $lowvalues = '';
my $highvalues = '';

my @params = split("\n",$string);

foreach (@params) {
	my $temp = $_;
	$paramnames = $temp if ($temp =~ /^-ppn/);
	$paramnames =~ s/-ppn:|\\$// if $paramnames;
	$paramnames =~ s/\s$// if $paramnames;
	$defaultvalues = $temp if ($temp =~ /^-ppd/);
	$defaultvalues =~ s/-ppd:|\\$// if $defaultvalues;
	$defaultvalues =~ s/\s$// if $defaultvalues;
	$lowvalues = $temp if ($temp =~ /^-ppl/);
	$lowvalues =~ s/-ppl:|\\$// if $lowvalues;
	$lowvalues =~ s/\s$// if $lowvalues;
	$highvalues = $temp if ($temp =~ /^-ppu/);
	$highvalues =~ s/-ppu:|\\$// if $highvalues;
	$highvalues =~ s/\s$// if $highvalues;
}

if ($debug) {
	print "params : $paramnames\n";
	print "default: $defaultvalues\n";
	print "lowval : $lowvalues\n";
	print "highval: $highvalues\n";
}

my @names = split(",",$paramnames);
my @defaults = split(",",$defaultvalues);
my @lowvals = split(",",$lowvalues);
my @highvals = split(",",$highvalues);

#verify equal quantites of parameters
die "Error : incoherent number of parameters" if ( grep {$_ != $#defaults} ($#lowvals, $#highvals, $#names) );
die "Error : empty parameters" if ( grep {$_ == -1} ($#defaults, $#lowvals, $#highvals, $#names) );

my %grostruc;
push( @{$grostruc{"paramnames"}} ,@names);
push( @{$grostruc{"defaultvalues"}} ,@defaults);
push( @{$grostruc{"lowvalues"}} ,@lowvals);
push( @{$grostruc{"highvalues"}} ,@highvals);

print Dumper \%grostruc;