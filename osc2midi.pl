#!/usr/bin/perl
use strict;
use warnings;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;

# INIT MIDI
#------------
my @alsa_output = ("astruxbridge",0);
#create alsa midi port with only 1 output
#client($name, $ninputports, $noutputports, $createqueue)
my $status = MIDI::ALSA::client("astruxbridge",0,1,0) || die "could not create alsa midi port.\n";
print "successfully created alsa midi port\n";

# INIT OSC
#------------
my $osc = Protocol::OSC->new;
my $oscport = 4000;
#create OSC input socket
my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $oscport, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
print "successfully created OSC UDP port $oscport\n";
 
 while (1) {
    $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
    my $p = $osc->parse($packet);
	
	my $path = $p->path;
	print "path=$path\n";
	my $type = $p->type;
	print "type=$type\n";

	my @args = $p->args;
	print "arg=$_\n" foreach @args;
	}
	
#	see also
# http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl/Server.pm