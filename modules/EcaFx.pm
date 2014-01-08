#!/usr/bin/perl

package EcaFx;

use base qw(EcaStrip EcaEcs);

use strict;
use warnings;
use feature 'state';

use Data::Dumper;

use lib '/home/seijitsu/astrux/modules';
use Bridge;
use Project qw($baseurl);

my $debug = 0;

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
sub new {
	my $class = shift;
	my $effect = shift;
	my $km = shift;
	state $position = 0;
	
	$position++;
	#TODO : find solution to give an number for inserts
	my $ecafx = {
		"fxname" => $effect,
		"generatekm" => $km,
		"ecsline" => "",
		"position" => $position
	};
	bless $ecafx,$class;
	
	$ecafx->init if $effect ne "";

	return $ecafx;
}

sub init {
	my $ecafx = shift;
	
	my $effect = $ecafx->{fxname};
	my $km = $ecafx->{midi_controls};

	#get effect controls
	if ($ecafx->GetControls($effect)) {
		#construit la ligne d'effet ecs
		my $defaults = join ',', @{$ecafx->{defaultvalues}};
		$ecafx->{ecsline} = " -pn:$effect," . $defaults;

		#ajouter les contrôleurs midi ?
		$ecafx->Generate_km if ($ecafx->{generatekm});
	}
	
}

sub GetControls() {
	my $ecafx = shift;
	my $plugin = shift;

	return 0 if !$plugin; 
	
	#open effect file
	my $file;
	#TODO : path is not generic !!
	my $string = '';
	if (open($file, "<", "/home/seijitsu/2.TestProject/ecacfg/effect_presets")) {
		#get the effect parameters string
		my $found =0;
		my $tic = 0;
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
		#close file
		close($file) || warn "close failed: $!";
		if ($found eq 0) {
			warn "Plugin $plugin not found\n";
			return 0;
		}
	}
	# TODO : fallback from project file to global file
	# warn "cannot open effect_presets file : $!";
	# return 0;

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
	if ( grep {$_ != $#defaults} ($#lowvals, $#highvals, $#names) ) {
			warn "Error : incoherent number of parameters";
			return 0;
	}
	if ( grep {$_ == -1} ($#defaults, $#lowvals, $#highvals, $#names) ) {
			warn "Error : empty parameters";
			return 0;
	}

	#insert values
	push( @{$ecafx->{paramnames}} ,@names);
	push( @{$ecafx->{defaultvalues}} ,@defaults);
	push( @{$ecafx->{lowvalues}} ,@lowvals);
	push( @{$ecafx->{highvalues}} ,@highvals);

	#print Dumper $ecafx;
	return 1;
}

sub getnextCC {
	state $channel = 1;
	state $CC = 0;
	#verify end of midi CC range
	die "CC max range error!!\n" if (($CC eq 127) and ($channel eq 16));
	#CC range from 1 to 127, update channel if needed
	if ($CC == 127) {
		$CC = 0;
		$channel++;
	}
	#increment CC number
	$CC++;
	#return values
	return($CC,$channel);
}

sub Generate_km {
	#grab plugin name in parameter
	my $ecafx = shift;
	my $plugin = shift;
	
	my @lows = @{$ecafx->{lowvalues}};
	my @highs = @{$ecafx->{highvalues}};

	#iterate through each parameter
	my $nb =1;
	foreach my $param (@{$ecafx->{paramnames}}) {
		#get mim/max parameter range, and new unique CC/channel
		my ($CC,$channel) = &getnextCC();
		my $low = (shift @lows);
		my $high = (shift @highs);
		$ecafx->{ecsline} .= " -km:" . $nb++ . ",$low,$high,$CC,$channel";
		#update the midistate.csv file
		#Bridge::Add_to_file($path . "/$param," . (shift @defaults) . ";$low;$high;$CC,$channel\n");
	}
	#remove trailing whitespace
	$ecafx->{ecsline} =~ s/\s+$//;
	return 1;		
}




1;