#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

# PERL midi = MIDI::ALSA
#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm

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
	return @osclines;
}

1;