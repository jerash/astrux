#!/usr/bin/perl

package Alsa;

use strict;
use warnings;

use MIDI::ALSA;
#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm

my @alsa_output = ("astruxbridge",0);
#create alsa midi port with only 1 output
#client($name, $ninputports, $noutputports, $createqueue)
my $status = MIDI::ALSA::client("astruxbridge",0,1,0);
#check status
die "could not create alsa midi port.\n" unless $status;
print "successfully created alsa midi port\n";

#connect to monitor
#connectto( $outputport, $dest_client, $dest_port )
$status = MIDI::ALSA::connectto( 0, 'Dispmidi:0' );
#check status
die "could not connect alsa midi port.\n" unless $status;
print "successfully connected alsa midi port\n";

my $value = 0;
while (1) {
	
	#build data packet
	#@CCdata= ($channel, unused,unused,unused, $param, $value)
	my @CC = (1, 7,'',$value,7,$value);

	#send midi data
	#output($type,$flags,$tag,$queue,$time,\@source,\@destination,\@data)
	$status = MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,\@CC);
	warn "could not send midi data\n" unless $status;

	$value++;
	sleep(1);
};

1;