#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl.pm
use Net::OpenSoundControl::Server;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;
use POSIX; #for ceil/floor function

# INIT MIDI
#------------
my @alsa_output = ("astruxbridge",0);
#create alsa midi port with only 1 output
#client($name, $ninputports, $noutputports, $createqueue)
my $status = MIDI::ALSA::client("astruxbridge",0,1,0) || die "could not create alsa midi port.\n";
print "successfully created alsa midi port\n";

# INIT OSC
#------------
my $oscport = 8000;
my $oscserver = Net::OpenSoundControl::Server->new(
      Port => $oscport, Handler => \&DoTheBridge) or
      die "Could not start server: $@\n";

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
$oscserver->readloop();

# FUNCTIONS
#------------------------------------------------------
sub DoTheBridge {
	my ($sender, $machin) = @_;
	#print Dumper @_;
	my @message = @{$machin};
	# print "path=$message[0]\n";
	# print "type=$message[1]\n";
	# print "value=$message[2]\n";

	my $path = $message[0];


	#check if received message can be translated
	if (exists $rules{$path}) {
		my $inval = $message[2];
		#get elements
		my $min = $rules{$path}[1];
		my $max = $rules{$path}[2];
		my $CC = $rules{$path}[3];
		my $channel = $rules{$path}[4];
		#print "I've found you !!! $inval $min $max $CC $channel\n";
		return if (
			!defined $inval or
			!defined $min or
			!defined $max or
			!defined $CC or
			!defined $channel
			);
		
		#verify if data is within min max range
		$inval = $min if $inval < $min;
		$inval = $max if $inval > $max;
		
		#scale value to midi range
		my $outval = floor((127*($inval-$min))/($max-$min)) ;
		# print "outval=$outval\n";
		
		#verify if outdata is within min max range
		$outval = 0 if $outval < 0;
		$outval = 127 if $outval > 127;
		
		#send midi data
		my @outCC = ($channel-1, '','','',$CC,$outval);
		#$status = MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,\@outCC);
		warn "could not send midi data\n" unless &SendCC(\@outCC);
		#update value in structure
		$rules{$path}[0] = $outval;
	}
	elsif ($path =~ /^\/bridge/) {
		print "Are you talking to me ? ok i'm leaving !\n";
		exit(0) if ($message[2] eq "quit");
	}
	elsif ($path =~ /^\/reload/) {
		#TODO send current values to sender
	}
	elsif ($path =~ /^\/ping/) {
		#TODO send pong back for keep alive info
	}
	else {
		print "ignored= ";
		print "$_ " foreach @message;
		print "\n";
	}
}

sub ScaleValue {
	#return floor((127*($inval-$min))/($max-$min));
}

sub SendCC {
	my $outCC = shift;
	return MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,$outCC);
}
#TODO clean exit with save and update oscmidistate.csv

#see also
# http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl/Server.pm