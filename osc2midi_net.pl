#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

#http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl.pm
use Net::OpenSoundControl::Server;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;
use POSIX; #for ceil/floor function

my %rules; #hash where the rules are stocked

# Catch TERM signal to save data
$SIG{'INT'} = sub {
	print "Oh oh we need to stop\nSAVING STATE\n";
	&SaveFile;
};

sub SaveFile {
	open FILE, ">/home/seijitsu/2.TestProject/files/oscmidistate.csv" or die $!;
	foreach my $path (keys %rules) {
		my $value = $rules{$path}[0];
		my $min = $rules{$path}[1];
		my $max = $rules{$path}[2];
		my $CC = $rules{$path}[3];
		my $channel = $rules{$path}[4];
		print FILE "$path;$value;$min;$max;$CC;$channel\n";
	}
	close FILE;	
}

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
		
		#update value in structure
		$rules{$path}[0] = $inval;
		
		my $outval = &ScaleValue($inval,$min,$max);

		#send midi data
		my @outCC = ($channel-1, '','','',$CC,$outval);
		#$status = MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,\@outCC);
		warn "could not send midi data\n" unless &SendCC(\@outCC);
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
	my $inval = shift;
	my $min = shift;
	my $max = shift;
	#verify if data is within min max range
	$inval = $min if $inval < $min;
	$inval = $max if $inval > $max;
	#scale value
	my $out = floor((127*($inval-$min))/($max-$min));
	#verify if outdata is within MIDI min max range
	$out = 0 if $out < 0;
	$out = 127 if $out > 127;
	#return scaled value
	return $out;
}

sub SendCC {
	my $outCC = shift;
	return MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,$outCC);
}

#see also
# http://search.cpan.org/~crenz/Net-OpenSoundControl-0.05/lib/Net/OpenSoundControl/Server.pm

