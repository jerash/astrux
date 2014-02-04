#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;
use POSIX qw(ceil floor); #for floor/ceil function

my $debug = 0;

###########################################################
#
#		 BRIDGE OBJECT functions
#
###########################################################

###########################################################
#
#		 BRIDGE FILE functions
#
###########################################################

sub create  {
	my $bridge = shift;

	my $filepath = $bridge->{file};
	open FILE, ">$filepath" or die $!;
	print FILE "path;type;value;min;max;[CC;channel]\n";
	close FILE;
	$bridge->{status} = "new";
}

sub save {
	my $bridge = shift;

	my $filepath = $bridge->{file};
	open FILE, ">>$filepath" or die $!;
	#add lines
	print FILE "$_\n" foreach @{$bridge->{lines}};
	close FILE;
}

sub create_lines {
	my $class = shift;
	my $project = shift;

	#the rule set
	my @osclines;
	# --- LOOP THROUGH MIXERs ---
	foreach my $mixername (keys %{$project->{mixers}}) {
		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};
		# --- LOOP THROUGH CHANNELS ---
		foreach my $channelname (keys %{$mixer}) {
			#create channel reference
			my $channel = $mixer->{$channelname};
			#add channel options
			push(@osclines,"/$mixername/$channelname/mute;ecs;0;0;1");
			push(@osclines,"/$mixername/$channelname/solo;ecs;0;0;1") unless $channel->is_hardware_out;
			push(@osclines,"/$mixername/$channelname/bypass;ecs;0;0;1");
			# --- LOOP THROUGH INSERTS ---
			foreach my $insertname (keys %{$channel->{inserts}}) {
				#create insert reference
				my $insert = $channel->{inserts}{$insertname};
				# --- LOOP THROUGH INSERT PARAMETERS ---
				my $i = 0;
				foreach my $paramname (@{$insert->{paramnames}}) {
					#construct line with
					# /mixername/channelname/insertname/paramname;midi;value;min;max;CC;channel
					warn "Insert ($paramname) has a system name... may not work\n" if ($paramname =~ /^(mute|solo|bypass)$/);
					my $value = $insert->{defaultvalues}[$i];
					my $min = $insert->{lowvalues}[$i];
					my $max = $insert->{highvalues}[$i];
					my ($CC,$channel) = ('','');
					($CC,$channel) = split(',',$insert->{CCs}[$i]) if $insert->{CCs}; #ignore if CC not created					
					my $line = "/$mixername/$channelname/$insertname/$paramname;midi;$value;$min;$max;$CC;$channel";
					push(@osclines,$line);
					# print "**$line \n";
					$i++;
				}
			}
			# --- LOOP THROUGH AUX ROUTES ---
			foreach my $auxroute (keys %{$channel->{aux_route}}) {
				#create route reference
				my $route = $channel->{aux_route}{$auxroute}{inserts}{panvol};
				# --- LOOP THROUGH route PARAMETERS ---
				my $i = 0;
				foreach my $paramname (@{$route->{paramnames}}) {
					#construct line with
					# /mixername/channelname/aux_to/route/paramname;midi;value;min;max;CC;channel
					my $value = $route->{defaultvalues}[$i];
					my $min = $route->{lowvalues}[$i];
					my $max = $route->{highvalues}[$i];
					my ($CC,$channel) = ('','');
					($CC,$channel) = split(',',$route->{CCs}[$i]) if $route->{CCs}; #ignore if CC not created					
					my $line = "/$mixername/$channelname/aux_to/$auxroute/$paramname;midi;$value;$min;$max;$CC;$channel";
					push(@osclines,$line);
					$i++;
				}
			}
		}
	}

	#TODO (osc2midi) integrate this loop above, this is just a temporrary workaround
	my @templines = @osclines;
	my %rules;
	foreach (@templines) { #fill the hash with the file info
		chomp($_);
		my @values = split(';',$_);
		my $path = shift @values;
		$rules{$path} = ();
		push @{$rules{$path}} , @values;
	}
	$project->{osc2midi}{rules} = \%rules;


	return @osclines;
}

sub create_midi_out_port {
	my $bridge = shift;

	#create alsa midi port with only 1 output
	my @alsa_output = ("astrux",0);

	#update bridge structure
	$bridge->{midiout} = @alsa_output;

	#client($name, $ninputports, $noutputports, $createqueue)
	my $status = MIDI::ALSA::client("astrux",0,1,0) || die "could not create alsa midi port.\n";
	print "successfully created alsa midi out port\n";
	$bridge->{status} = 'created';
}

sub send_osc2midi {
	my $bridge = shift;
	my $path = shift;
	my $inval = shift;
	
	print "in osc2midi\n" if $debug;
	
	#create a hash of rules, TODO change to use the project info
	my %rules = %{$bridge->{rules}};
	#check if received message can be translated
	if (exists $rules{$path}) {
		#get elements
		my $type = $rules{$path}[0];
		return if $type eq 'ecs';
		my $default = $rules{$path}[1];
		my $min = $rules{$path}[2];
		my $max = $rules{$path}[3];
		my $CC = $rules{$path}[4];
		my $channel = $rules{$path}[5];
		print "I've found you !!! $inval $min $max $CC $channel\n" if $debug;

		if (	!defined $type or
				!defined $inval or
				!defined $min or
				!defined $max or
				!defined $CC or
				!defined $channel
				) {
			warn "something is missing in type=$type inval=$inval min=$min max=$max CC=$CC channel=$channel\n";
			return;
		}
		
		#update value in structure
		# $rules{$path}[1] = $inval;
		
		#scale value to midirange
		my $outval = &ScaleValue($inval,$min,$max);
		print "value scaled to $outval\n" if $debug;

		#prepare midi data
		my @outCC = ($channel-1, '','','',$CC,$outval);
		my @alsa_output = $bridge->{midiout};
		#send midi data
		warn "could not send midi data\n" unless MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,\@outCC);
	}
	else {
		print "ignored=$path $inval\n";
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


sub Refresh {
	my $bridge = shift;

	my %rules = %{$bridge->{rules}};

	print "Sending all midi data!!\n";
	foreach my $path (keys %rules) {
		#get elements
		my $type = $rules{$path}[0];
		my $inval = $rules{$path}[1];
		my $min = $rules{$path}[2];
		my $max = $rules{$path}[3];
		my $CC = $rules{$path}[4];
		my $channel = $rules{$path}[5];

		next if (
			!defined $type or
			!defined $inval or
			!defined $min or
			!defined $max or
			!defined $CC or
			!defined $channel
			);
		#print "inval=$inval min=$min max=$max CC=$CC channel=$channel\n";

		if ($type eq "midi"){
			my $outval = &ScaleValue($inval,$min,$max);
			#send midi data
			my @outCC = ($channel-1, '','','',$CC,$outval);
			warn "could not send midi data\n" unless &SendCC(\@outCC);
		}
		#TODO check for non midi type !
	}
}

1;