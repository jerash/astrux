#!/usr/bin/perl

package Project;

use strict;
use warnings;

use Mixer;
use Song;
use Plumbing;
use Bridge;

#-------------------------------------GENERATION-----------------------------------------------------

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

	#------------------Add songs------------------------------
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	$project->AddPlumbing;

	#----------------Add bridge-----------------------------
	$project->AddOscMidiBridge;
}

sub AddMixers {
	my $project = shift;

	#build path to mixers files
	my $mixers_path = $project->{project}{base_path} . "/" . $project->{project}{mixers_path};
	
	#iterate through each mixer file
	my @files = <$mixers_path/*.ini>;
	foreach my $mixerfile (@files) {

		#create mixer
	 	print "Project: Creating mixer from $mixerfile\n";
	 	my $mixer = Mixer->new($mixerfile);
		$project->{mixers}{$mixer->{ecasound}{name}} = $mixer;
	}

	#verify if there is one "main" mixer
	if (!exists $project->{mixers}{"main"} ) {
		die "!!!! main mixer must exist !!!!!\n";
	}
}

sub AddSongs {
	my $project = shift;

	#build path to songs folder
	my $songs_path = $project->{project}{base_path} . "/" . $project->{project}{songs_path};
	
	#get song list
	my @songs_folders = <$songs_path/*>;

	#iterate through each song fodlder
	foreach my $folder (@songs_folders){

		#ignore files, use directories only
		next if (! -d $folder);
		print "Project: Entering song folder : $folder\n";

		#crete a song object
		my $song = Song->new($folder);

		#update the project with song info
		$project->{songs}{$song->{song_globals}{name}} = $song;
	}
}

sub AddOscMidiBridge {	
	my $project = shift;
	
	$project->{bridge}{status} = "notcreated";
	bless $project->{bridge}, Bridge::;

	my @bridgelines = Bridge->create_lines($project);
	$project->{bridge}{lines} = \@bridgelines;
}

sub AddPlumbing {
	my $project = shift;

	my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
	$project->{connections}{file} = $plumbingfilepath;
	bless $project->{connections} , Plumbing::;

	my @plumbing_rules = Plumbing->create_rules($project);
	$project->{connections}{rules} = \@plumbing_rules;
}

sub GenerateFiles {
	my $project = shift;

	#----------------ECASOUND FILES------------------------
	#for each mixer, create the ecasound mixer file
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shorcut name
		my $mixer = $project->{mixers}{$mixername};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/".$mixer->{ecasound}{name} . ".ecs";
		#add path to ecasound info
		$mixer->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $mixer->{ecasound} , EcaEngine::;
		#create the file
		$mixer->{ecasound}->create;
		#add ecasound header to file
		$mixer->{ecasound}->build_header;
		#get chains from structure
		$mixer->get_ecasoundchains;
		#add chains to file
		$mixer->{ecasound}->add_chains;
		#TODO verify is the generated file can be opened by ecasound
		#$mixer->{ecasound}->verify;
	}

	#for each song, create the ecasound player file		
	foreach my $songname (keys %{$project->{songs}}) {
		#shorcut name
		my $song = $project->{songs}{$songname};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/songs/$songname/chainsetup.ecs";
		#add path to song info
		$song->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $song->{ecasound} , EcaEngine::;
		#create the file
		$song->{ecasound}->create;
		#copy header from player mixer
		if (defined $project->{mixers}{players}{ecasound}{header}) {
			$song->{ecasound}{header} = $project->{mixers}{players}{ecasound}{header};
			#replace -n:"players" with song name to have unique chainsetup name
			$song->{ecasound}{header} =~ s/-n:\"players\"/-n:\"$songname\"/;
		}
		else {
			die "Error : can't find a player mixer header\n";
		}
		#add ecasound header to file
		$song->build_song_header;
		#add chains to file
		$song->add_songfile_chain;
		#TODO verify is the generated file can be opened by ecasound
		#$song->{ecasound}->verify;
	}

	#----------------PLUMBING FILE------------------------
	if ($project->{connections}{"jack.plumbing"} == 1) {
		#we're asked to generate the plumbing file
		my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
		$project->{connections}{file} = $plumbingfilepath;
		# bless $project->{connections} , Plumbing::;
		print "Project: creating plumbing file $plumbingfilepath\n";
		$project->{connections}->create;
		$project->{connections}->save;
	}
	else {
		print "Project: jack.plumbing isn't defined as active. Not creating file.";
	}

	#----------------OSC2MIDI BRIDGE FILE------------------------
	#TODO define bridge option
	if ($project->{controls}{osc2midi} == 1) {
		#we're asked to generate the bridge file
		my $filepath = $project->{project}{base_path} . "/" . $project->{project}{output_path} . "/oscmidistate.csv";
		$project->{osc2midi}{file} = $filepath;
		print "Project: creating osc2midi file $filepath\n";
		$project->{osc2midi}->create;
		$project->{osc2midi}->save;
	}
	else {
		print "Project: midi2osc bridge isn't defined as active. Not creating file.";
	}

}

sub SaveTofile {
	my $project = shift;
	my $outfile = shift;

	#we create a dumper file (human readable)
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	open my $handle, ">$outfile.dmp" or die $!;
	print $handle Dumper $project;
	close $handle;

	#remove all filehandles from structure (storable limitation)
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
		$hash{mixers}{$mixer} = delete $project->{mixers}{$mixer}{ecasound}{socket}; 
	}

	#Storable : create a project file, not working with opened sockets
	$outfile .= ".cfg";
	use Storable;
	$Storable::Deparse = 1; #warn if CODE encountered
	store $project, $outfile;

	#store values back
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
		$project->{mixers}{$mixer}{ecasound}{socket} = delete $hash{mixers}{$mixer}; 
	}
	undef %hash;

}

sub LoadFromFile {
	my $project = shift;
	my $infile = shift;

	# use Storable;
	# $project = retrieve($infile);

	my $in = open "<$infile";
    local($/) = "";
    my $str = <$in>;
    close $in;

    print "Input: $str";

    my $hashref;
    eval $str;
    my(%hash) = %$hashref;

    foreach my $key (sort keys %hash)
    {
        print "$key: @{$hash{$key}}\n";
    }

}

#-------------------------------------LIVE COMMANDS-----------------------------------------------------
sub StartEngines {
	my $project = shift;
	#reload if $engine->is_running
	#$engine->StartMixer
	foreach my $mixername (keys %{$project->{mixers}}) {
		print " - mixer $mixername\n";
		my $mixerfile = $project->{mixers}{$mixername}{ecasound}{ecsfile};
		my $path = $project->{project}{base_path}."/".$project->{project}{eca_cfg_path};
		my $port = $project->{mixers}{$mixername}{ecasound}{port};
		
		#if mixer is already running on same port, then reconfigure it
		if  ($project->{mixers}{$mixername}{ecasound}->is_running) {
			print "    Found existing Ecasound engine on port $port, reconfiguring engine\n";
			#create socket for communication
			$project->{mixers}{$mixername}{ecasound}->init_socket($port);
			#reconfigure ecasound engine with ecs file
			$project->{mixers}{$mixername}{ecasound}->LoadAndStart;
			next;	
		}

		#if mixer is not existing, launch mixer with needed file
		my $command = "ecasound -q -s $mixerfile -R $path/ecasoundrc --server --server-tcp-port=$port > /dev/null 2>&1 &\n";
		system ( $command );
		#wait for ecasound engines to be ready
		sleep(1) until $project->{mixers}{$mixername}{ecasound}->is_ready;
		print "   Ecasound $mixername is ready\n";
		#create socket for communication
		$project->{mixers}{$mixername}{ecasound}->init_socket($port);
	}
}

sub execute_command {
	my $project = shift;
	my $command = shift;

	my $reply = '';

	if ($command =~ /^save$/) { 
		$project->SaveTofile("$project->{project}{name}"); 
	}
	elsif ($command =~ /^status$/) { 
		foreach my $mixer (keys %{$project->{mixers}}) {
			$reply = $project->{mixers}{$mixer}{ecasound}->Status . "\n";
		}
	}
	elsif ($command =~ /^song /) { 
		my $songname = substr $command,5;
		return unless exists $project->{songs}{$songname};
		$reply = "Starting song $songname\n";
		#loading players
		$reply .= $project->{mixers}{players}{ecasound}->SelectAndConnectChainsetup($songname);
		#loading midifile
		#TODO oups...jpmidi cannot load a new song & need a2jmidid to connect to some midi out
		#autostart ?
		$reply .= $project->{mixers}{players}{ecasound}->SendCmdGetReply("start") 
			if $project->{songs}{$songname}{song_globals}{autostart};
	}
	elsif ($command =~ /^play$/) { 
		$reply = "Starting play\n";
		$reply .= $project->{mixers}{players}{ecasound}->SendCmdGetReply("start");
	}
	elsif ($command =~ /^stop$/) { 
		$reply = "Stopping\n";
		$reply .= $project->{mixers}{players}{ecasound}->SendCmdGetReply("stop");
	}
	elsif ($command =~ /^zero$/) { 
		$reply = "bac