#!/usr/bin/perl

package Plumbing;

use strict;
use warnings;

sub create {
	#create the file (overwrite)
	my $connections = shift;

	#get path to file
	my $path = $connections->{file};
	die "no path to create plumbing file\n" unless (defined $path);
	
	#create an empty file (overwrite existing)
	#TODO : check for existence and ask for action
	open my $handle, ">$path" or die $!;
	#update mixer status
	$connections->{status} = "new";
	#close file
	close $handle;
}

sub save {
	my $connections = shift;

	if (defined $connections->{status}) {
		open my $handle, ">>$connections->{file}" or die $!;
		print $handle "$_\n" for @{$connections->{rules}};
		close $handle;
	} else {
		#TODO better handling
		warn "Plumbing file doesn't exist!!\n";
	}
}

sub create_rules {
	my $class = shift;
	my $project = shift;

	#the rule set
	my @rules;

	# --- LOOP THROUGH MIXERs ---
	foreach my $mixername (keys %{$project->{mixers}}) {
		#ignore players mixer
		next if $project->{mixers}{$mixername}{ecasound}{name} eq "players";
		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};
		# --- LOOP THROUGH CHANNELS ---
		foreach my $channelname (keys %{$mixer}) {
				for my $i (1..2) {
				#get the table of connections
				my @table = @{$mixer->{$channelname}{connect}};
				#take the Nth one, will be undef if connect is empty or undef
				my $plumbin = $table[$i-1]; 
				my $plumbout = $project->{mixers}{$mixername}{ecasound}{name}.":$channelname"."_$i";
				#jack plumbing will need a certain order for hardware connects
				if ($mixer->{$channelname}->is_hardware_out) {
					push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
				}
				else {
					push (@rules , "(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
				}
			}
			#if this is a bus out, create generic channels routing to this bus
			if ($mixer->{$channelname}->is_hardware_out) {
				my $string = "(connect \"$mixername:to_bus_$channelname"."_.*[13579]\$"."\" \"$mixername:bus_$channelname"."_1\")";
				push (@rules , $string); 
				$string = "(connect \"$mixername:to_bus_$channelname"."_.*[02468]\$"."\" \"$mixername:bus_$channelname"."_2\")";
				push (@rules , $string); 
			}
		}
	}
	return @rules;
}

1;