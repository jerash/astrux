#!/usr/bin/perl

package MidiCC;

use strict;
use warnings;

use feature 'state';
use Data::Dumper;

#----------------------------------------------------------------
#
# === midi controller ===
#
# -km:1,-30,12,87,10
# -km:operator,min,max,CC,channel
 
# call with $ret = &getnextCC();
# $ret will have the last CC value
sub getnextCC {
	my @midiCCchannel = (0,1);
	#verify end of midi CC range
	die "CC max range error!!\n" if (($midiCCchannel[0] eq 127) and ($midiCCchannel[1] eq 16));
	#CC range from 1 to 127, update channel if needed
	if ($midiCCchannel[0] == 127) {
		$midiCCchannel[0] = 0;
		$midiCCchannel[1]++;
	}
	#increment CC number
	$midiCCchannel[0]++;
}

#will return a line containing the uniques km CCs
sub generate_km {
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
		#return (1,%pluginfo)
		return (1,"this is ok");
		#for each parameters, generate a -km:
	}

	&getnextCC();
	my $line = "-km:1,0,100," . $midiCCchannel[0] . "," . $midiCCchannel[1];
}	
#TBD : get plugin range
#DOING : make decision to use ecasound effect_preset file exclusively to standardize format

# print @midiCCchannel;
# print "\n";
# print &getvolkmops();
# print "\n";
# print &getvolkmops();
# print "\n";
# print &getvolkmops();

1;