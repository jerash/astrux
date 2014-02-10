#!/usr/bin/perl

package Plumbing;

use strict;
use warnings;

###########################################################
#
#		 PLUMBING OBJECT functions
#
###########################################################

sub create {
	#create the file (overwrite)
	my $connections = shift;

	#get path to file
	my $path = $connections->{file};
	die "no path to create plumbing file\n" unless (defined $path);
	
	#create an empty file (overwrite existing)
	open my $handle, ">$path" or die $!;
	#update mixer status
	$connections->{status} = "new";
	#close file
	close $handle;
}

###########################################################
#
#		 PLUMBING functions
#
###########################################################

sub create_rules {
	my $class = shift;
	my $project = shift;

	#the rule set
	my @rules;

	# --- LOOP THROUGH MIXERs ---
	foreach my $mixername (keys %{$project->{mixers}}) {
		#ignore players mixer
		next if $project->{mixers}{$mixername}{engine}{name} eq "players";
		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};
		#deal with engine type
		if ($project->{mixers}{$mixername}->is_ecasound) {
			# --- LOOP THROUGH CHANNELS ---
			foreach my $channelname (keys %{$mixer}) {
				#get the table of connections
				my @table = @{$mixer->{$channelname}{connect}};
				#for each channel (assumed max 2 channels)
				for my $i (1..2) {
					#take the Nth one, will be undef if connect is empty or undef
					my $plumbin = $table[$i-1]; 
					my $plumbout = $project->{mixers}{$mixername}{engine}{name}.":$channelname"."_$i";
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
		elsif ($project->{mixers}{$mixername}->is_nonmixer) {
			# --- FIRST GET MAIN OUT AND AUXES ---
			my $main_out;
			my @auxes;
			foreach my $channelname (keys %{$mixer}) {
				if ($mixer->{$channelname}->is_main_out) {
					$main_out = $channelname;
				}
				if ($mixer->{$channelname}->is_aux) {
					push @auxes, $channelname;
				}
			}
			# --- LOOP THROUGH CHANNELS ---
			foreach my $channelname (keys %{$mixer}) {
				# --- INPUTS ---
				if ($mixer->{$channelname}->is_main_in) {
					#get the table of hardware input connections
					my @table = @{$mixer->{$channelname}{connect}};
					#for each channel (assumed max 2 channels)
					for my $i (1..2) {
						#take the Nth one, will be undef if connect is empty or undef
						my $plumbin = $table[$i-1];
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:in-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/in-$i"
							if ($mixer->{$channelname}{group} ne '');
						#add rule
						push (@rules , "(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
					}
					#add the route to master
					for my $i (1..2) {
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/out-$i"
							if ($mixer->{$channelname}{group} ne '');
						my $plumbin;
						$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$main_out:in-$i"
							if ($mixer->{$main_out}{group} eq '');
						$plumbin = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$main_out}{group}."):$main_out/in-$i"
							if ($mixer->{$main_out}{group} ne '');
						#add rule
						push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
					}
					#add the routes to aux
					foreach my $aux (@auxes) {
						for my $i (1..2) {
							my $plumbout;
							$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:".$mixer->{$aux}{is_aux}."/out-$i"
								if ($mixer->{$channelname}{group} eq '');
							$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/".$mixer->{$aux}{is_aux}."/out-$i"
								if ($mixer->{$channelname}{group} ne '');
							my $plumbin;
							$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$aux:in-$i"
								if ($mixer->{$aux}{group} eq '');
							$plumbin = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$aux}{group}."):$aux/in-$i"
								if ($mixer->{$aux}{group} ne '');
							#add rule
							push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
						}
					}
				}
				# --- SEND AUXES ---
				elsif ($mixer->{$channelname}->is_send) {
				#add the route to master
					for my $i (1..2) {
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/out-$i"
							if ($mixer->{$channelname}{group} ne '');
						my $plumbin;
						$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$main_out:in-$i"
							if ($mixer->{$main_out}{group} eq '');
						$plumbin = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$main_out}{group}."):$main_out/in-$i"
							if ($mixer->{$main_out}{group} ne '');
						#add rule
						push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
					}
				}
				# --- BUS OUTPUT ---
				elsif ($mixer->{$channelname}->is_bus_out) {
					#get the table of hardware output connections
					my @table = @{$mixer->{$channelname}{connect}};
					#add the route to master
					for my $i (1..2) {
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/out-$i"
							if ($mixer->{$channelname}{group} ne '');
						my $plumbin = $table[$i-1];
						#add rule
						push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
					}
				}
				# --- MAIN OUTPUT ---
				elsif ($mixer->{$channelname}->is_main_out) {
					#get the table of hardware output connections
					my @table = @{$mixer->{$channelname}{connect}};
					#for each channel (assumed max 2 channels)
					for my $i (1..2) {
						#take the Nth one, will be undef if connect is empty or undef
						my $plumbin = $table[$i-1];
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." (".$mixer->{$channelname}{group}."):$channelname/out-$i"
							if ($mixer->{$channelname}{group} ne '');
						#add rule
						push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
					}
				}
				else {
					die "Plumbing Error: untreated channel type $mixer->{$channelname}{type}";
				}

			}
		}
		else {
			die "Plumbing Error: unknown mixer type\n";
		}
	}
	return @rules;
}

###########################################################
#
#		 PLUMBING FILE functions
#
###########################################################

sub save {
	my $connections = shift;

	if (defined $connections->{status}) {
		open my $handle, ">>$connections->{file}" or die $!;
		print $handle "$_\n" for @{$connections->{rules}};
		close $handle;
	} else {
		warn "Plumbing file has not been initialized!!\n";
	}
}

1;