#!/usr/bin/perl
use strict;
use warnings;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

my $osc = Protocol::OSC->new;
#make packet
#my $data = $osc->message(my @specs = qw(/main/mic_raf/panvol/volume_db f 1));
#my $data = $osc->message(my @specs = qw(/bridge s quit));
#my $data = $osc->message(my @specs = qw(/toto i 8943));
my $data = $osc->message(my @specs = qw(/refresh i 1));
#    # or
    #use Time::HiRes 'time';
    #my $data $osc->bundle(time, [@specs], [@specs2], ...);
	
#send
my $udp = IO::Socket::INET->new( PeerAddr => 'localhost', PeerPort => '8000', Proto => 'udp', Type => SOCK_DGRAM) || die $!;
$udp->send($data);