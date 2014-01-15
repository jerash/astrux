#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;

# sub new {
      # my $class = shift;
      # open my $file, ">$files_folder/oscmidistate.csv" or die $!;
      # bless $file, $class;
      # return $file;
# }

		#update the midistate.csv file
		#Bridge::Add_to_file($path . "/$param," . (shift @defaults) . ";$low;$high;$CC,$channel\n");

sub create  {
	my $bridge = shift;

	my $filepath = $bridge->{file};
	open FILE, ">$filepath" or die $!;
	print FILE "path;value;min;max;CC;channel\n";
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
			# --- LOOP THROUGH INSERTS ---
			foreach my $insertname (keys %{$channel->{inserts}}) {
				#create insert reference
				my $insert = $channel->{inserts}{$insertname};
				# --- LOOP THROUGH INSERT PARAMETERS ---
				my $i = 0;
				foreach my $paramname (@{$insert->{paramnames}}) {
					#construct line with
					# /mixername/channelname/insertname/paramname;value;min;max;CC;channel
					my $value = $insert->{defaultvalues}[$i];
					my $min = $insert->{lowvalues}[$i];
					my $max = $insert->{highvalues}[$i];
					my ($CC,$channel) = ('','');
					($CC,$channel) = split(',',$insert->{CCs}[$i]) if $insert->{CCs}; #ignore if CC not created					
					my $line = "/$mixername/$channelname/$insertname/$paramname;$value;$min;$max;$CC;$channel";
					push(@osclines,$line);
					# print "**$line \n";
					$i++;
				}
			}
		}
	}
	#TODO : find a way to acces channels routing CCs
	return @osclines;
}

1;