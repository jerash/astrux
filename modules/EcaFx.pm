#!/usr/bin/perl

package EcaFx;

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
# input : $plugin = plugin name define in effect_preset file to find
#
# return ($code,$string,%hash)
#	$code : 0 = error/not found, 1 = ok
#	$string : "error message" if code 0, "ok" if code 1
#	%hash : empty hash if code 0, hash of controls if code 1
#
#------------------------------------------------------------------------------------------
sub getcontrols() {
	my $debug = 0;

	#name of plugin passed as argument (may be an incomplete name)
	my $plugin = shift;

	#check for existing single argument
	return (0,"usage : getecafxcontrols \“pluginname\" \n",{}) if !$plugin; 
	
	#open effect file
	open(my $file, "<", "effect_presets")
		or return (0,"cannot open < effect_presets: $!",{});

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
	return (0,"Plugin $plugin not found\n",{}) if ($found eq 0);
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
	return (0,"Error : incoherent number of parameters",{}) if ( grep {$_ != $#defaults} ($#lowvals, $#highvals, $#names) );
	return (0,"Error : empty parameters",{}) if ( grep {$_ == -1} ($#defaults, $#lowvals, $#highvals, $#names) );

	my %grostruc;
	push( @{$grostruc{"paramnames"}} ,@names);
	push( @{$grostruc{"defaultvalues"}} ,@defaults);
	push( @{$grostruc{"lowvalues"}} ,@lowvals);
	push( @{$grostruc{"highvalues"}} ,@highvals);

	#print Dumper \%grostruc;
	return (1,"ok",%grostruc);
}

1;