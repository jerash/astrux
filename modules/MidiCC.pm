#!/usr/bin/perl

package MidiCC;
#----------------------------------------------------------------
#
# === midi controller ===
#
# -km:1,-30,12,87,10
# -km:operator,min,max,CC,channel
#
# use ecasound effect_preset file exclusively to standardize format

use strict;
use warnings;

use feature 'state';
use Data::Dumper;
use Config::IniFiles;

require ("EcaFx.pm");

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini"; # -allowempty => 1;
die "reading project ini file failed\n" until $ini_project;
#folder where to store generated files
my $files_folder = $ini_project->val('project','filesfolder');

#----------------------------------------------------------------
#
# === getnextCC ===
#
#will return the next uniques CCs available
#
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

#----------------------------------------------------------------
#
# === generate_km ===
#
# param1 : plugin name
# param2 : current tree path
#
# will return a line containing the uniques km CCs
# and create a file with all paths to the midi CC
#
sub generate_km {
	#grab plugin name in parameter
	my $plugin = shift;
	my $path = shift; #print "$name\n";
	#get plugin info
	my ($code,$message,%pluginfo) = EcaFx::getcontrols($plugin);
	if ($code eq 0) {
		#can't get plugin controls
		print "$message\n";
		return (0,"");
	}
	else {
		print Dumper \%pluginfo if $debug;
		open FILE, ">>$files_folder/oscmidistate.csv" or die $!;
		#iterate through each parameter
		my @names = values $pluginfo{"paramnames"};
		my @defaults = values $pluginfo{"defaultvalues"};
		my @lows = values $pluginfo{"lowvalues"};
		my @highs = values $pluginfo{"highvalues"};
		my $nb = 1;
		my $line = "";
		foreach my $param (@names) {
			#get mim/max parameter range, and new unique CC/channel
			my ($CC,$channel) = &getnextCC();
			my $low = (shift @lows);
			my $high = (shift @highs);
			$line .= " -km:" . $nb++ . ",$low,$high,$CC,$channel";
			#TODO : create/update the midistate.csv file
			print FILE $path . "/$param," . (shift @defaults) . ",$low,$high,$CC,$channel\n";
		}
		close FILE;
		#remove trailing whitespace
		$line =~ s/\s+$//;
		return (1,$line);		
	}
}

#----------------------------------------------------------------
#
# === get_defaults ===
#
#will return a line containing the uniques the default values
# separated by ,
#
sub get_defaults {
	#grab plugin name in parameter
	my $plugin = shift;
	#get plugin info
	my ($code,$message,%pluginfo) = EcaFx::getcontrols($plugin);
	if ($code eq 0) {
		#can't get plugin controls
		print "$message\n";
		return (0,"");
	}
	else {
		print Dumper \%pluginfo if $debug;
		#iterate through each parameter
		my @defaults = values $pluginfo{"defaultvalues"};
		my $line = "";
		foreach my $param (@defaults) {
			$line .= "," . $param;
		}
		return (1,$line);		
	}
}	

1;