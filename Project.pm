#!/usr/bin/perl

package Project;

use strict;
use warnings;

use Mixer;
use Meters;
use Song;
use Plumbing;
use Bridge;
use TouchOSC;
use Jack;
use Metronome;

###########################################################
#
#		 PROJECT OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $ini_file = shift;

	#init structure
	my $project = {
		'mixers' => {},
		'songs' => {},
	};
	bless $project,$class;

	#if parameter exist, fill from ini file
	$project->init($ini_file) if defined $ini_file;

	return $project; 
}

sub init {
	#grap Project object from argument
	my $project = shift;
	my $ini_project = shift;

	#merge project ini info
	%$project = ( %{$ini_project} , %$project );

	#------------------Add mixers-----------------------------
	$project->AddMixers;

	# sanitize effects values, need SAMPLERATE
	$project->Sanitize;

	#------------------Add meters------------------------------
	$project->AddMeters;

	#------------------Add meters------------------------------
	$project->AddMetronome;

	#------------------Add songs------------------------------
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	# MOVED to generate files, after we know the nonmixer auxes

	#----------------Add bridge-----------------------------
	$project->AddBridge;
}

sub Start {
	my $project = shift;

	#----------------------------------------------------------------
	# verify services and servers
	#----------------------------------------------------------------

	# JACK server
	#---------------------------------
	$project->Jack::Start_Jack_Server;

	# jack-plumbing
	#---------------------------------
	$project->{plumbing}->Start;

	#JACK-OSC (jack.clock)
	#---------------------------------
	$project->Jack::Start_Jack_OSC;

	# alsa to jack MIDI bridge (a2jmidid)
	#---------------------------------
	$project->Jack::Start_a2jmidid;

	#klick
	#---------------------------------
	$project->{metronome}->Start;

	#JPMIDI << TODO problem in server mode can't load new midi file....
	#---------------------------------
	# my $pid_jpmidi = qx(pgrep jpmidi);
	# if ($project->{midi_player}{enable}) {
	# 	die "JPMIDI server is not running" unless $pid_jpmidi;
	# 	print "JPMIDI server running with PID $pid_jpmidi";
	# }
	# $project->{midi_player}{PID} = $pid_jpmidi;

	#SAMPLER
	#---------------------------------
	my $pid_linuxsampler = qx(pgrep linuxsampler);
	#TODO check linuxsampler is running on the expected port
	if ($project->{linuxsampler}{enable}) {
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler";
		$project->{LINUXSAMPLER}{PID} = $pid_linuxsampler;
	}

	#----------------------------------------------------------------
	# start mixers
	#----------------------------------------------------------------
	print "Starting mixers engines\n";
	$project->StartEngines;

	#----------------------------------------------------------------
	# load song chainsetups + dummy
	#----------------------------------------------------------------
	my @songkeys = sort keys %{$project->{songs}};
	print "SONGS :\n";
	foreach my $song (@songkeys) {
		#load song chainsetup
		print " - $project->{songs}{$song}{friendly_name}\n";
		print $project->{mixers}{players}{engine}->LoadFromFile($project->{songs}{$song}{ecasound}{ecsfile});
	}
	#load dummy song chainsetup
	$project->{mixers}{players}{engine}->SelectAndConnectChainsetup("players");

	#----------------------------------------------------------------
	# Start meters
	#----------------------------------------------------------------

	#TODO make sure all jack ports are active before starting meters
	$project->{meters}->Start if $project->{meters}{enable};

	#----------------------------------------------------------------
	# Start bridge > wait loop
	#----------------------------------------------------------------
	print "\n--------- Project $project->{globals}{name} Running---------\n";
	$project->{bridge}->Start;
}

###########################################################
#
#		 PROJECT ADD functions
#
###########################################################

sub AddMixers {
	my $project = shift;

	my $foundmain = 0;

	#build path to mixers files
	die "Project Error: missing output_path in project.ini\n" unless exists $project->{globals}{output_path};
	my $output_path = $project->{globals}{base_path} . "/" . $project->{globals}{output_path};
	
	#iterate through each mixer file
	foreach (keys $project->{mixerfiles}) {

	 	#build complete path to file
		my $mixerfile = $project->{globals}{base_path} . "/" . 
						$project->{globals}{mixers_path} . "/" . 
						$project->{mixerfiles}{$_};
		die "Project Error: Bad mixerfile reference $mixerfile in project.ini\n" unless (-e $mixerfile);

	 	print "Project: Creating mixer from $mixerfile\n";

		#create mixer
	 	my $mixer = Mixer->new($mixerfile,$output_path);
	 	die "could not create mixer" unless $mixer;

	 	#insert into project
		$project->{mixers}{$mixer->{engine}{name}} = $mixer;

		#check if we have a main mixer
		if ($project->{mixers}{$mixer->{engine}{name}}->is_main) {
			die "Error ...hum we already have a main mixer, can't have two !\n" if $foundmain eq 1;
			$foundmain = 1;
		}
	}

	#verify if there is one "main" mixer
	die "!!!! main mixer must exist !!!!!\n" unless $foundmain;
}

sub AddSongs {
	my $project = shift;

	#iterate through each song fodlder
	foreach (keys $project->{songfiles}) {

	 	#build complete path to file
		my $songfile = $project->{globals}{base_path} . "/" . 
						$project->{globals}{songs_path} . "/" . 
						$project->{songfiles}{$_};
		die "Bad song ini reference $songfile in project.ini\n" unless (-e $songfile);

	 	print "Project: Creating song from $songfile\n";

		#crete a song object
		my $song = Song->new($songfile);
	 	die "could not create song" unless $song;
	 	#add markers if any
	 	my $output_path = $project->{globals}{base_path} . "/" . 
						$project->{globals}{songs_path} . "/" . 
						$song->{name};
	 	$song->add_markers($output_path);

	 	#insert into project
		$project->{songs}{$song->{name}} = $song;
	}
}

sub AddBridge {	
	my $project = shift;

	#verify if bridge ini file exists
	my $bridgefile = $project->{globals}{base_path} . "/project/bridge.ini";
	die "Project error : could not find bridge ini file $bridgefile, aborting.\n" unless (-e $bridgefile);

	#insert into project
	$project->{bridge} = Bridge->new($bridgefile);

	#add statefile path to bridge
	$project->{bridge}{statefile} = $project->{globals}{base_path} . "/" . 
									$project->{globals}{output_path} . "/". 
									$project->{globals}{name} . ".state";
}

sub AddPlumbing {
	my $project = shift;

	#build destination file path
	my $plumbingfilepath = $project->{globals}{base_path}."/".$project->{globals}{output_path}."/jack.plumbing";

	#create object
	$project->{plumbing} = Plumbing->new($plumbingfilepath);

	#get rules
	my @plumbing_rules = $project->Plumbing::get_plumbing_rules;

	#insert into project
	$project->{plumbing}{rules} = \@plumbing_rules;
}

sub AddMIDIOSCPaths {
	my $project = shift;

	#build osc destination file path
	my $filepath = $project->{globals}{base_path} . "/" . $project->{globals}{output_path} . "/osc.csv";
	$project->{bridge}{OSC}{file} = $filepath;
	#build midi destination file path
	$filepath = $project->{globals}{base_path} . "/" . $project->{globals}{output_path} . "/midi.csv";
	$project->{bridge}{MIDI}{file} = $filepath;

	#create midi/osc paths
	$project->Bridge::create_midiosc_paths;
}

sub AddMeters {
	my $project = shift;
	return unless $project->{meters}{enable};

	print "Project: Creating meters\n";

	#create object
	$project->{meters} = Meters->new($project->{meters});

	#insert meters info into project
	$project->{meters}{values} = $project->Meters::get_meters_hash;
}

sub AddMetronome {
	my $project = shift;
	return unless $project->{metronome}{enable};

	print "Project: Creating metronome\n";

	#create object
	$project->{metronome} = Metronome->new($project->{metronome});
}

###########################################################
#
#		 PROJECT functions
#
###########################################################
sub Sanitize {
	my $project = shift;

	print "Project: Sanitize\n";
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shortcut name
		my $mixer = $project->{mixers}{$mixername};
		#sanitize effect
		$mixer->Sanitize_EffectsParams($project->{jack}{samplerate});
	}
	print " |_Done\n";
}

###########################################################
#
#		 PROJECT FILE functions
#
###########################################################

sub GenerateFiles {
	my $project = shift;

	print "Project: generating files\n";


	#----------------DUMPER FILE------------------------
	$project->SaveDumperFile(".pre");

	#----------------MIXERS FILES------------------------
	#for each mixer, create the mixer file/folder
	foreach my $mixername (keys %{$project->{mixers}}) {
		my $mixer = $project->{mixers}{$mixername}->Create_File;
	}

	#----------------SONGS FILES------------------------
	#for each song, create the ecasound player file		
	foreach my $songname (keys %{$project->{songs}}) {
		#shorcut name
		my $song = $project->{songs}{$songname};

		#copy ecasound parameters from players mixer
		my %engine = %{$project->{mixers}{players}{engine}};
		$song->{ecasound} = \%engine;
		bless $song->{ecasound} , EcaEngine::;

		#update info with song name
		$song->{ecasound}{name} = $songname;

		#update ecsfile path
		my $ecsfilepath = $project->{globals}{base_path}."/songs/$songname/chainsetup.ecs";
		$song->{ecasound}{ecsfile} = $ecsfilepath;

		#add io_chains
		$song->build_songfile_chain;
		#create the file
		$song->{ecasound}->CreateEcsFile;
		#remove io_chains
		delete $song->{ecasound}{io_chains} if defined $song->{ecasound}{io_chains};

		#create tempo/timebase/markers file
		my $output_path = $project->{globals}{base_path}."/songs/$songname";
		$song->save_markers_file($output_path);
		$song->save_klick_tempomap_file($output_path) if ($project->{metronome}{enable}) and ($project->{metronome}{engine} eq "klick");
	}

	#----------------PLUMBING FILE------------------------

	if ( $project->{plumbing}{enable} ) {

		# add the pumbing rules to the project 	
		# we do it now after nonmixer files are generated, so we know the auxes assignations
		$project->AddPlumbing;

		#now generate the file
		print " |_Project: creating plumbing file $project->{plumbing}{file}\n";
		$project->{plumbing}->save_to_file;
	}
	else {
		print " |_Project: jack.plumbing isn't defined as active. Not creating file.\n";
	}

	#----------------OSC BRIDGE FILE------------------------
	if ($project->{bridge}{OSC}{enable}) {

		# we do it now after nonmixer files are generated, so we know the auxes assignations

		#create the OSC paths
		$project->AddMIDIOSCPaths;
		print " |_Project: creating OSC paths file $project->{bridge}{OSC}{file}\n";
		
		# translate osc paths
		$project->Bridge::translate_osc_paths_to_target;

		#now generate the file
		$project->{bridge}->save_osc_file;
	}
	else {
		print " |_Project: bridge isn't defined as active. Not creating files.";
	}

	#----------------MIDI BRIDGE FILE------------------------
	if ($project->{bridge}{MIDI}{enable}) {
		print " |_Project: creating MIDI paths file $project->{bridge}{MIDI}{file}\n";
		# we do it now after osc files are generated, so we know the paths
		$project->{bridge}->save_midi_file;		
	}

	#----------------TOUCHOSC PRESETS FILES------------------------
	if ($project->{touchosc}{enable}) {
		$project->TouchOSC::save_touchosc_files;
	}

	#----------------DUMPER FILE------------------------
	$project->SaveDumperFile;
}

sub SaveDumperFile {
	my $project = shift;
	my $suffix = shift;

	my $outfile = $project->{globals}{name};	
	#replace any nonalphanumeric character
	$outfile =~ s/[^\w]/_/g;
	$outfile .= $suffix if $suffix;
	$outfile = $project->{globals}{base_path}."/". $project->{globals}{output_path} ."/$outfile.dmp";
	#create a dumper file (human readable)
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	open my $handle, ">$outfile" or die $!;
	print $handle Dumper $project;
	close $handle;
	print " |_Project: creating dumper file $outfile\n";
}

sub SaveToFile {
	my $project = shift;

	print "Project: saving project\n";
	my $outfile = ("$project->{globals}{name}");
	#replace any nonalphanumeric character
	$outfile =~ s/[^\w]/_/g;
	#create the complete file path
	$outfile = $project->{globals}{base_path}."/".$outfile . ".cfg";

	# remove all filehandles from structure (storable limitation)
	# also remove AE containing sub (CODE)
	my %hash;
	if (defined $project->{bridge}{TCP}{socket}) {
		$hash{TCP}{socket} = delete $project->{bridge}{TCP}{socket};
		$hash{TCP}{events} = delete $project->{bridge}{TCP}{events};
	}
	if (defined $project->{bridge}{OSC}{socket}) {
		$hash{OSC}{socket} = delete $project->{bridge}{OSC}{socket};
		$hash{OSC}{object} = delete $project->{bridge}{OSC}{object};
		$hash{OSC}{events} = delete $project->{bridge}{OSC}{events};
	}
	if (defined $project->{meters}{events}) {
		$hash{meters}{events} = delete $project->{meters}{events};
	}
	if (defined $project->{meters}{pipefh}) {
		$hash{meters}{pipefh} = delete $project->{meters}{pipefh};
	}
	foreach my $mixer (keys $project->{mixers}) {
		$hash{mixers}{$mixer} = delete $project->{mixers}{$mixer}{engine}{socket}; 
	}

	#Storable : create a project file, not working with opened sockets
	use Storable;
	# $Storable::forgive_me = 1; #the fatal message is turned in a warning and some meaningless string is stored instead
	$Storable::Deparse = 1; #warn if CODE encountered, but dont die
	store $project, $outfile;

	print " |_Project: saved to $outfile\n";

	# store values back
	if (defined $hash{TCP}{socket}) {
		$project->{bridge}{TCP}{socket} = delete $hash{TCP}{socket};
		$project->{bridge}{TCP}{events} = delete $hash{TCP}{events};
	}
	if (defined $hash{OSC}{socket}) {
		$project->{bridge}{OSC}{socket} = delete $hash{OSC}{socket};
		$project->{bridge}{OSC}{object} = delete $hash{OSC}{object};
		$project->{bridge}{OSC}{events} = delete $hash{OSC}{events};
	}
	if (defined $hash{meters}{events}) {
		$project->{meters}{events} = delete $hash{meters}{events};
	}
	if (defined $hash{meters}{pipefh}) {
		$project->{meters}{pipefh} = delete $hash{meters}{pipefh};
	}
	foreach my $mixer (keys $hash{mixers}) {
		$project->{mixers}{$mixer}{engine}{socket} = delete $hash{mixers}{$mixer}; 
	}
	undef %hash;
}

sub LoadFromFile {
	my $project = shift;
	my $infile = shift;

	use Storable;
	$project = retrieve($infile);
}

sub RemoveOldFiles {
	my $project = shift;

	my $old_statefile = $project->{globals}{base_path} ."/". $project->{globals}{output_path} . "/$project->{globals}{name}.state";
	if (-e $old_statefile) {
		print "deleting old state file $old_statefile\n";
		unlink $old_statefile;
	}
	warn "Old state file $old_statefile could not be deleted\n" if -e $old_statefile;

	#TODO remove ... well everything in "output" folder
	#TODO remove songs tempo.map / markers.csv / chainsetup.ecs
}

###########################################################
#
#		 PROJECT LIVE functions
#
###########################################################

sub StartEngines {
	my $project = shift;

	foreach my $mixername (keys %{$project->{mixers}}) {
		print " - mixer $mixername\n";
		$project->{mixers}{$mixername}->Start;
	}
}

1;
