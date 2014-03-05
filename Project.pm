#!/usr/bin/perl

package Project;

use strict;
use warnings;

use Mixer;
use Song;
use Plumbing;
use Bridge;
use TouchOSC;

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

	#------------------Add songs------------------------------
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	# MOVED to generate files, after we know the nonmixer auxes

	#----------------Add bridge-----------------------------
	$project->AddBridge;
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

	 	print "Project: Creating songs from $songfile\n";

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
		$song->create_markers_file($output_path);
		$song->create_tempomap_file($output_path);
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

sub SaveTofile {
	my $project = shift;

	print "Project: saving project\n";
	my $outfile = ("$project->{globals}{name}");
	#replace any nonalphanumeric character
	$outfile =~ s/[^\w]/_/g;
	#create the complete file path
	$outfile = $project->{globals}{base_path}."/".$outfile . ".cfg";

	# remove all filehandles from structure (storable limitation)
	#TODO also remove AE containing sub (CODE)
	my %hash;
	if (defined $project->{TCP}{socket}) {
		$hash{TCP}{socket} = delete $project->{TCP}{socket};
		$hash{TCP}{events} = delete $project->{TCP}{events};
	}
	if (defined $project->{OSC}{socket}) {
		$hash{OSC}{socket} = delete $project->{OSC}{socket};
		$hash{OSC}{object} = delete $project->{OSC}{object};
		$hash{OSC}{events} = delete $project->{OSC}{events};
	}
	foreach my $mixer (keys $project->{mixers}) {
		$hash{mixers}{$mixer} = delete $project->{mixers}{$mixer}{engine}{socket}; 
	}

	#Storable : create a project file, not working with opened sockets
	use Storable;
	$Storable::Deparse = 1; #warn if CODE encountered, but dont die
	store $project, $outfile;

	print " |_Project: saved to $outfile\n";

	# store values back
	if (defined $hash{TCP}{socket}) {
		$project->{TCP}{socket} = delete $hash{TCP}{socket};
		$project->{TCP}{events} = delete $hash{TCP}{events};
	}
	if (defined $hash{OSC}{socket}) {
		$project->{OSC}{socket} = delete $hash{OSC}{socket};
		$project->{OSC}{object} = delete $hash{OSC}{object};
		$project->{OSC}{events} = delete $hash{OSC}{events};
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
