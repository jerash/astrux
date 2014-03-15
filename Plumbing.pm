#!/usr/bin/perl

package Plumbing;

use strict;
use warnings;

###########################################################
#
#		 PLUMBING OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $plumbingfile = shift;
	die "Plumbing Error: can't create bridge without an destination filename\n" unless $plumbingfile;

	#init structure
	my $plumbing = {
		"file" => $plumbingfile,
		"enable" => '1'
	};
	
	bless $plumbing,$class;
	
	return $plumbing; 
}

sub init {
	my $plumbing = shift;
	my $project = shift;

	#create the rules
	my @plumbing_rules = $plumbing->give_me_the_rules($project);
	
	#insert into project
	$plumbing->{rules} = \@plumbing_rules;
}

sub Start {
	my $project_plumbing = shift;
	#jack.plumbing (unused, replaced with jack-plumbing)
	#---------------------------------
	# copy jack plumbing file
	# if ( $project_plumbing->{enable} eq '1') {
	# 	my $homedir = $ENV{HOME};
	# 	warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
	# 	use File::Copy;
	# 	copy("$project_plumbing->{file}","$homedir/.jack.plumbing") or die "jack.plumbing copy failed: $!";
	# }
	# # start jack.plumbing
	# my $pid_jackplumbing = qx(pgrep jack.plumbing);
	# if ($project_plumbing->{enable}) {
	# 	if (!$pid_jackplumbing) {
	# 		print "jack.plumbing is not running. Starting it\n";
	# 		my $command = "jack.plumbing > /dev/null 2>&1 &";
	# 		system ($command);
	# 		sleep 1;
	# 		$pid_jackplumbing = qx(pgrep jack.plumbing);
	# 	}
	# 	print "jack.plumbing running with PID $pid_jackplumbing";
	# }
	# $project_plumbing->{PID} = $pid_jackplumbing;

	#jack-plumbing
	#---------------------------------
	if ( $project_plumbing->{enable} ) {
		# start jack-plumbing
		my $pid_jackplumbing;
		my $file_jackplumbing,
		my @lines = qx(pgrep -a jack-plumbing);

		if ($#lines > 0) {
			die "Error: multiple jack-plumbing instances found\n";
		}
		elsif ($#lines == -1) {
			print "jack-plumbing is not running. Starting it with file $project_plumbing->{file}\n";
			die "Could not find plumbing file $project_plumbing->{file}" unless -e $project_plumbing->{file};
			my $command = "jack-plumbing -q $project_plumbing->{file} >/dev/null 2>&1 &";
			system ($command);
			sleep 1;
			$pid_jackplumbing = qx(pgrep jack-plumbing);
			chomp $pid_jackplumbing;
		}
		elsif ($#lines == 0) {
			if ( $lines[0] =~ /(\d+?) jack-plumbing -q (.*)/ ) {
				$pid_jackplumbing = $1;
				$file_jackplumbing = $2;
				die "found jack-plumbing instance using another rule file : $lines[0]\n" 
					unless $file_jackplumbing eq $project_plumbing->{file};
			}
			else {
				die "jack-plumbing doesn\'t have expected parameters : $lines[0]\n";
			}
		}
		print "jack-plumbing running with PID $pid_jackplumbing and file $file_jackplumbing\n";
		$project_plumbing->{PID} = $pid_jackplumbing;
	}
	else {
		print "jack-plumbing disabled in project\n";
	}
}

###########################################################
#
#		 PLUMBING FILE functions
#
###########################################################

sub save_to_file {
	my $plumbing = shift;

	#get path to file
	my $path = $plumbing->{file};
	die "Plumbing error: no path to create plumbing file\n" unless (defined $path);

	warn "Plumbing rules are empty....\n" unless @{$plumbing->{rules}};

	#create the file (overwrite)
	open my $handle, ">$plumbing->{file}" or die $!;
	print $handle "$_\n" for @{$plumbing->{rules}};
	close $handle;
}

###########################################################
#
#		 PLUMBING functions
#
###########################################################

sub get_plumbing_rules {
	my $project = shift;

	#the rule set
	my @rules;

	# --- LOOP THROUGH MIXERs ---

	foreach my $mixername (keys %{$project->{mixers}}) {
		
		#ignore players mixer, plumbing is generic on main mixer player tracks
		next if $project->{mixers}{$mixername}{engine}{name} eq "players";
		
		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};

		# --- IF SUBMIX ---

		if ($project->{mixers}{$mixername}->is_submix) {
			
			# first get submix out channel
			my $main_out;
			foreach my $channelname (keys %{$mixer}) {
				if ($mixer->{$channelname}->is_submix_out) {
					$main_out = $channelname;
				}
			}
			# then create routes
			foreach my $channelname (keys %{$mixer}) {
				if ( $mixer->{$channelname}->is_submix_in ) {

					#get number of channels
					my $channels = $mixer->{$channelname}{channels};
					#for each channel
					for my $i (1..$channels) {
						
						my $plumbin;
						my $plumbout;
						# all submix inputs strips need connect to submix output strip
						if ($project->{mixers}{$mixername}->is_nonmixer) {
							$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
								if ($mixer->{$channelname}{group} eq '');
							$plumbin = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/out-$i"
								if ($mixer->{$channelname}{group} ne '');
							
							$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$main_out:in-$i"
								if ($mixer->{$main_out}{group} eq '');
							$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$main_out}{group}."\\):$main_out/in-$i"
								if ($mixer->{$main_out}{group} ne '');
						}
						if ($project->{mixers}{$mixername}->is_ecasound) {
							#TODO ecasound sumbix plumbing rules
						}
						#add rule
						push (@rules , "(connect \"$plumbin\" \"$plumbout\")") if $plumbin;

						#get the table of hardware input connections
						my @table = @{$mixer->{$channelname}{connect}};
						# connect submix inputs if they are mentioned
						if (@table){ 
							$plumbin = $table[$i-1];
							$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:in-$i"
								if ($mixer->{$channelname}{group} eq '');
							$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/in-$i"
								if ($mixer->{$channelname}{group} ne '');
							#add rule
							push (@rules , "(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
						}
					}
				}
				# elsif ( $mixer->{$channelname}->is_submix_out ) {
				# 	#nothing to do, plumbing is made on main mixer submix tracks
				# }
			}
			#rules are done for the mixer, go to next mixer
			next;
		}

		# --- DEPENDING ON ENGINE TYPE ---

		if ($project->{mixers}{$mixername}->is_ecasound) {

			# --- LOOP THROUGH CHANNELS ---

			foreach my $channelname (keys %{$mixer}) {
				#get the table of connections
				my @table = @{$mixer->{$channelname}{connect}};
				my $channels = $mixer->{$channelname}{channels};
				#for each channel
				for my $i (1..$channels) {
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

			my @auxes = $project->{mixers}{$mixername}->get_auxes_list;
			my $main_out = $project->{mixers}{$mixername}->get_main_out;

			# --- LOOP THROUGH CHANNELS ---

			foreach my $channelname (keys %{$mixer}) {

				my $channels = $mixer->{$channelname}{channels};

				# --- INPUTS ---

				if ($mixer->{$channelname}->is_main_in) {
					#get the table of hardware input connections
					my @table = @{$mixer->{$channelname}{connect}};
					#for each channel
					for my $i (1..$channels) {
						#take the Nth one, will be undef if connect is empty or undef
						my $plumbin = $table[$i-1];
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:in-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/in-$i"
							if ($mixer->{$channelname}{group} ne '');
						#add rule
						push (@rules , "(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
					}

					#force chanels to 2, as mono tracks have been converted to stereo
					$channels = 2;
					
					if (!$project->{mixers}{$mixername}{engine}{autoconnect}) {
						#add the route to master
						for my $i (1..$channels) {
							my $plumbout;
							$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
								if ($mixer->{$channelname}{group} eq '');
							$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/out-$i"
								if ($mixer->{$channelname}{group} ne '');
							my $plumbin;
							$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$main_out:in-$i"
								if ($mixer->{$main_out}{group} eq '');
							$plumbin = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$main_out}{group}."\\):$main_out/in-$i"
								if ($mixer->{$main_out}{group} ne '');
							#add rule
							push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
						}

						#add the routes to aux
						foreach my $aux (@auxes) {
							next if ((defined $project->{mixers}{$mixername}{channels}{$aux}{return}) and ($project->{mixers}{$mixername}{channels}{$aux}{return} eq $channelname)); #don't create an aux route to myself
							for my $i (1..$channels) {
								my $plumbout;
								$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:aux-".$mixer->{$aux}{aux_letter}."/out-$i"
									if ($mixer->{$channelname}{group} eq '');
								$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/aux-".$mixer->{$aux}{aux_letter}."/out-$i"
									if ($mixer->{$channelname}{group} ne '');
								my $plumbin;
								$plumbin = $project->{mixers}{$mixername}{engine}{name}."/$aux:in-$i"
									if ($mixer->{$aux}{group} eq '');
								$plumbin = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$aux}{group}."\\):$aux/in-$i"
									if ($mixer->{$aux}{group} ne '');
								#add rule
								push (@rules , "(connect \"$plumbout\" \"$plumbin\")") if $plumbin;
							}
						}
					}
				}
				
				# --- BUS OUTPUT --- SEND AUXES ---

				elsif ($mixer->{$channelname}->is_bus_out or $mixer->{$channelname}->is_send) {
					#get the table of hardware output connections
					my @table = @{$mixer->{$channelname}{connect}};
					#specific case for monowed outputs, force only 1 output channel for correct plumbing
					$channels = 1 if ((defined $mixer->{$channelname}{mode}) and ($mixer->{$channelname}{mode} eq "mono"));
					#add the routes to outputs
					for my $i (1..$channels) {
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/out-$i"
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
					for my $i (1..$channels) {
						#take the Nth one, will be undef if connect is empty or undef
						my $plumbin = $table[$i-1];
						my $plumbout;
						$plumbout = $project->{mixers}{$mixername}{engine}{name}."/$channelname:out-$i"
							if ($mixer->{$channelname}{group} eq '');
						$plumbout = $project->{mixers}{$mixername}{engine}{name}." \\(".$mixer->{$channelname}{group}."\\):$channelname/out-$i"
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


1;