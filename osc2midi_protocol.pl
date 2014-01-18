#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#http://search.cpan.org/~egor/Protocol-OSC-0.03/lib/Protocol/OSC.pod#Dispatching
use Protocol::OSC;
use IO::Socket::INET;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;

use POSIX; #for ceil function

# INIT MIDI
#------------
my @alsa_output = ("astruxbridge",0);
#create alsa midi port with only 1 output
#client($name, $ninputports, $noutputports, $createqueue)
my $status = MIDI::ALSA::client("astruxbridge",0,1,0) || die "could not create alsa midi port.\n";
print "successfully created alsa midi port\n";

#connect to monitor
#connectto( $outputport, $dest_client, $dest_port )
$status = MIDI::ALSA::connectto( 0, 'Dispmidi:0' );
#check status
die "could not connect alsa midi port.\n" unless $status;
print "successfully connected alsa midi port\n";

# INIT OSC
#------------
my $osc = Protocol::OSC->new;
my $oscport = 7001;
#create OSC input socket
my $in = IO::Socket::INET->new( qw(LocalAddr localhost LocalPort), $oscport, qw(Proto udp Type), SOCK_DGRAM ) || die $!;
print "successfully created OSC UDP port $oscport\n";

# LOAD BRIDGE RULES FILE
#------------------------
open FILE, "</home/seijitsu/2.TestProject/files/oscmidistate.csv" or die $!;
my %rules;
while (<FILE>) { #fill the hash with the file info
	chomp($_);
	my @values = split(';',$_);
	my $path = shift @values;
	$rules{$path} = ();
	push @{$rules{$path}} , @values;
}
close FILE;
#print Dumper %rules;
#TODO we may need a "type" flag on each line...

# START WAITING FOR OSC PACKETS (using Protocol::OSC)
#------------------------------------------------------
while (1) {
	#wait for packet
    $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
    my $p = $osc->parse($packet);
	
	#grab arguments
	my @args = $p->args;
	my $path = $p->path;
	my $type = $p->type;
	
	#print debug info
	print "path=$path\n";
	print "type=$type\n";
	print "arg=$_\n" foreach @args;
	
	#check if received message must be translated
	if (exists $rules{$path}) {
		
		my $inval = $args[0];

		#get elements
		my $min = $rules{$path}[1];
		my $max = $rules{$path}[2];
		my $CC = $rules{$path}[3];
		my $channel = $rules{$path}[4];
		print "I've found you !!! $min $max $CC $channel\n";
		#scale value to midi range
		my $outval = ceil((127*($inval-$min))/($max-$min)) ;
		print "outval=$outval\n";
		#send midi data
		my @outCC = ($channel, '','','',$CC,$outval);
		$status = MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,\@outCC);
		warn "could not send midi data\n" unless $status;
		#update value in structure
		$rules{$path}[0] = $outval;
	}
	elsif ($path =~ /^\/bridge/) {
		print "Are you talking to me ?\n";
		exit(0) if ($args[0] eq "quit");
	}
	else {
		print "ignored=$path $args[0]\n";
	}
	
}

#TODO clean exit with save and update oscmidistate.csv

#see also
# http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl/Server.pm