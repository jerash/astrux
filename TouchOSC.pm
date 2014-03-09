#!/usr/bin/perl

package TouchOSC;

use strict;
use warnings;

use Data::Dumper;
my $debug = 1;

# Warnings :
# - in preset file vertical means horizontal, and vice-versa
# - in touchosc editor xy position is relative to upper-left corner of widget/screen
#   whereas in preset file it is relative to bottom-left corner of widget/screen
# - screen size defined in layout size is reduced by 40 vertical pixels for usable area

###########################################################
#
#		 TOUCHOSC GLOBAL definitions
#
###########################################################

my $xml_header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";

my @layout_iphone = (480,320);
my @layout_ipad = (1024,768);
my @layout_iphone5 = (568,320);
my @layout_custom = (480,320);
my $layouts = { #(x,y)
	iphone => \@layout_iphone,
	ipad => \@layout_ipad ,
	iphone5 => \@layout_iphone5,
	custom => \@layout_custom
};
my @colors = qw(red green blue yellow purple gray orange brown pink);
my @layout_orientations = qw(horizontal vertical);
my @layout_modes = qw(0);
my @response = qw(absolute relative);
my @type_fader = qw(faderh faderv);
my @type_rotary = qw(rotaryh rotaryv);

#defaults
my $default_layout = 'iphone';
my $default_color = 0;
my $default_layout_orientation = 0;
my $default_layout_mode = 0;
my $default_control_response = 1;
my $default_type_fader = 0;
my $default_type_rotary = 0;
my $default_text_size = 13;

# controls definitions  #TODO make it a hash with presets for each layout in %layouts
#-----------------------
my $astrux_controls = {
	vol_fader => &create_fader(200,50,"$colors[$default_color]"),
	aux_fader => &create_fader(157,50,"orange"),
	small_pot => &create_pot(50,50,"$colors[$default_color]"),
	big_pot => &create_pot(80,80,"$colors[$default_color]"),
	small_button => &create_button(50,50,"$colors[$default_color]"),
	small_push => &create_push(50,50,"$colors[$default_color]"),
	big_button => &create_button(80,80,"$colors[$default_color]"),
	track_label => &create_label(20,50,"$colors[$default_color]",13),
	aux_label => &create_label(20,50,"orange",13),
	monitor_label => &create_label(30,190,'gray',20),
	group_label => &create_label(30,155,"$colors[$default_color]",20),
	song_label => &create_label(50,145,"$colors[$default_color]",13),
	small_time => &create_label(50,75,"$colors[$default_color]",13),
	small_bbt => &create_label(50,75,"$colors[$default_color]",13)
};

###########################################################
#
#		 TOUCHOSC OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $options = shift; #hashref containing layout options

	my $layout_size = $options->{layout_size} || $default_layout;
	my $layout_orientation = $options->{layout_orientation} || $default_layout_orientation;
	my $layout_mode = $options->{layout_mode} || $default_layout_mode;

	#verify if passed info is usable
	if (! exists $layouts->{$layout_size} ) {
		warn "TouchOSC warning: could not find layout_size $layout_size. Fallback to default\n";
		$layout_size = $default_layout;
	}
	if (! grep( /^$layout_orientation$/, @layout_orientations ) ) {
		warn "TouchOSC warning: could not find layout_orientation $layout_orientation. Fallback to default\n";
		$layout_size = $layout_orientations[$default_layout_orientation];
	}
	if (! grep( /^$layout_mode$/, @layout_modes ) ) {
		warn "TouchOSC warning: could not find layout_mode $layout_mode. Fallback to default\n";
		$layout_mode = $layout_modes[$default_layout_mode];
	}

	#init structure with xml info
	my $touchosc = {
		header => $xml_header,
		layout_header => "<layout version=\"13\" mode=\"$layout_mode\" orientation=\"$layout_orientation\">",
		layout_footer => "</layout>",
		layout_size => $layout_size
	};
	bless $touchosc,$class;
	
	return $touchosc; 
}

###########################################################
#
#		 TOUCHOSC FILE functions
#
###########################################################

sub save_touchosc_files {
	my $project = shift;

	#get the touchosc presets
	my $touchoscpresets = $project->TouchOSC::get_touchosc_presets;

	foreach my $mixername (keys %{$touchoscpresets}) {

		foreach my $presetname (keys %{$touchoscpresets->{$mixername}}) {
			#save temporary xml file
			my $preset = $touchoscpresets->{$mixername}{$presetname};
			open FILE , ">/tmp/index.xml";
			print FILE $preset->{header};
			print FILE $preset->{layout_header};

			next unless $preset->{pages};
			foreach my $pagename (sort keys $preset->{pages}) {
				my $page = $preset->{pages}{$pagename};
				print FILE $page->{header};

				next unless $page->{controls};
				foreach my $controlname (sort keys $page->{controls}) {
					my $control = $page->{controls}{$controlname};
					my $line = '<control ';

					foreach my $ctrlval (sort keys %{$control}) {
						$line .= "$ctrlval=\"$control->{$ctrlval}\" ";
					}
					print FILE "$line></control>";
				}
				print FILE '</tabpage>';
			}
			print FILE $preset->{layout_footer};
			close FILE;
			#build output path
			my $path = $project->{globals}{base_path}."/".$project->{globals}{output_path}."/$presetname.touchosc";
			#zip temporary file as a touchosc preset file
			system("zip -j $path /tmp/index.xml > /dev/null 2>&1");
			#delete temporary xml file
			unlink "/tmp/index.xml";
		}
	}
}

###########################################################
#
#		 TOUCHOSC functions
#
###########################################################

# TODO if not exist plugin preset, make default

# rules pack = monitormix, monitorfx, main, song, markers, livescreen, system

# --- monitor layout for iphone size ---
# [ monitormix pages ] [ monitorfx pages  ] [ song      pages  ] [ markers  pages   ] [ livescreen pages ]
# { auxnam pagenam  M} { fxname pagenam   } { -- B -- B  start } {                  } { start stop zero  }
# { | | | | | | | | P} {  O  O  O  O    B } { -- B -- B  stop  } {   vertical       } { time bars/beats  }
# { | | | | | | | | |} {  O  O  O  O    G } { -- B -- B  zero  } {   list of        } {  markers name    }
# { | | | | | | | | |} {  O  O  O  O    G } { -- B -- B  time  } {    markers       } { - - - - - - -    }
# { - - - - - - - - -} {  -  -  -  -      } { -- B -- B  bars  } {                  } { ________________ }

# --- main layout for ipad size ---
#	

sub get_touchosc_presets {
	my $project = shift;

	my $options = \%{$project->{touchosc}};

	my %presets;
	
	foreach my $mixername (keys $project->{mixers}) {

		my $mixer = $project->{mixers}{$mixername};
		# --- GET INPUTS, AUXES, and MAIN OUT ---
		my @inputnames = $mixer->get_inputs_list; #main hardware in + submix ins
		my @auxnames = $mixer->get_auxes_list; #will build preset for each aux (hardware out + fx send loop)
		my $mainout = $mixer->get_main_out if $mixer->is_main; #will build preset for mainout (hardware out)
		my $submixout = $mixer->get_submix_out if $mixer->is_submix; #will build preset for submixout (submix out)

		#build presets for each aux
		#------------------------------
		foreach my $auxname (@auxnames) {
			
			if ( (!defined $mixer->{channels}{$auxname}{touchosc_pages}) or ($mixer->{channels}{$auxname}{touchosc_pages} eq '') ) {
				warn "TouchOSC error : could not find necessary info for channel $auxname";
				next;
			}

			print " |_TouchOSC: creating preset for aux $auxname in mixer $mixer->{engine}{name}\n";

			# add aux preset in the hashref 
			$presets{$mixername}{$auxname} = TouchOSC->new($options);

			# get layout dimensions # TODO create a specific size for each monitor (touchosc_layout)
			my $layout_size = $layouts->{$options->{layout_size}};
			use POSIX qw(ceil);

			my $control;
			my $color;
			my $control_index = 0;

			# create the mix pages with volume control
			if ($mixer->{channels}{$auxname}{touchosc_pages} =~ "monitormix") {

				my $max_channels_faders_per_page = int (($layout_size->[0] - 53) / 53);
				my $mix_pages_number = ceil( $#inputnames/$max_channels_faders_per_page );

				for my $pagenumber (1..$mix_pages_number) {
					#add volume faders page(s)
					$presets{$mixername}{$auxname}->add_page("Mix$pagenumber");
					print " | |_adding page Mix$pagenumber\n";
			
					#for each input channel, add a volume control
					for my $nb (0..($max_channels_faders_per_page-1)) {
						#get inputname from list of inputs
						my $inputname = $inputnames[$control_index];
						#get input's mixer group
						$color = &get_group_color($mixer->{channels}{$inputname}{group});
						# add input volume control fader
						$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","vol_fader","vol_$inputname");
						$control->set_control_position(2+53*($control_index-(($pagenumber-1)*$max_channels_faders_per_page)),20);
						$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
						$control->set_control_minmax(-60,6) if $mixer->is_ecasound;
						$control->set_control_name("vol_$inputname");
						$control->set_control_color($color);
						$control->set_control_oscpath("/$mixer->{engine}{name}/$inputname/aux_to/$auxname/vol");
						#add input label
						$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","track_label","label_$inputname");
						$control->set_control_name("label_$inputname");
						$control->set_control_color($color);
						$control->set_label_text("$inputname");
						$control->set_control_position(2+53*($control_index-(($pagenumber-1)*$max_channels_faders_per_page)),0);
						$control->set_control_oscpath("/dummy");
						#stop if we have done all inputs
						last if ++$control_index > $#inputnames;
					}
					#add aux master volume fader
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","aux_fader","vol_$auxname");
					$control->set_control_position($layout_size->[0]-53,20);
					$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
					$control->set_control_minmax(-60,6) if $mixer->is_ecasound;
					$control->set_control_name("vol_$auxname");
					$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/panvol/vol");
					#add aux master input label
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","aux_label","label_$auxname");
					$control->set_control_name("label_$auxname");
					$control->set_label_text("Volume");
					$control->set_control_position($layout_size->[0]-53,0);
					$control->set_control_oscpath("/dummy");
					#add aux master pan rotary
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","small_pot","pan_$auxname");
					$control->set_control_position($layout_size->[0]-53,176);
					$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
					$control->set_control_minmax(0,100) if $mixer->is_ecasound;
					$control->set_control_name("pan_$auxname");
					$control->set_control_color("orange");
					$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/panvol/pan");
					#add aux master mute label
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","aux_label","mutel_$auxname");
					$control->set_control_name("mutel_$auxname");
					$control->set_label_text("mute");
					$control->set_control_position($layout_size->[0]-53,243);
					$control->set_control_oscpath("/dummy");
					#add aux master mute button
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","small_button","mute_$auxname");
					$control->set_control_position($layout_size->[0]-53,227);
					$control->set_control_minmax(0,1);
					$control->set_control_name("mute_$auxname");
					$control->set_control_color("orange");
					$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/mute");
					#add page label
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","monitor_label","label1_$auxname");
					$control->set_control_name("label1_$auxname");
					$control->set_label_text("$auxname");
					$control->set_control_position(0,230);
					$control->set_control_oscpath("/dummy");
					#add page name
					$control = $presets{$mixername}{$auxname}->add_control("Mix$pagenumber","group_label","label2_$auxname");
					$control->set_control_name("label2_$auxname");
					$control->set_label_text("Mix$pagenumber/$mix_pages_number");
					$control->set_control_position(190,230);
					$control->set_control_oscpath("/dummy");
				}
			}

			# create the fx page(s) # TODO
			if ($mixer->{channels}{$auxname}{touchosc_pages} =~ "monitorfx") {
			}

			# create the song page(s) # TODO
			if ($mixer->{channels}{$auxname}{touchosc_pages} =~ "song") {

 				$control_index = 0;
 				# get songs
				my @songs = sort keys $project->{songs};
				my $max_songs_per_page = int (($layout_size->[1] - 42 )/ 53) * 2;
				my $column = 0;
				my $song_pages_number = ceil( $#songs/$max_songs_per_page );

				for my $pagenumber (1..$song_pages_number) {
					#add songs page(s)
					$presets{$mixername}{$auxname}->add_page("Songs$pagenumber");
					print " | |_adding page Songs$pagenumber\n";

					#for each song, add a label and start button
					for my $nb (0..($max_songs_per_page-1)) {

						#get songname from list of songs
						my $songname = $songs[$control_index];
						#add song label
						$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","song_label","label_$songname");
						$control->set_control_name("label_$songname");
						$control->set_control_color("blue");
						$control->set_label_text("$project->{songs}{$songname}{friendly_name}");
						$control->set_label_outline("false");
						$control->set_control_position(2+200*$column, (($control_index + 1) <= ($max_songs_per_page / 2)) ? 2+53*$control_index : 2+53*($control_index-($max_songs_per_page / 2)) );
						$control->set_control_oscpath("/dummysong");
						# add song select button
						$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_push","but_$songname");
						$control->set_control_position(147+200*$column, (($control_index + 1) <= ($max_songs_per_page / 2)) ? 4+53*$control_index : 4+53*($control_index-($max_songs_per_page / 2)) );
						$control->set_control_minmax(0,1);
						$control->set_control_name("but_$songname");
						$control->set_control_color("orange");
						$control->set_control_oscpath("/song/$songname");
						#update column number
						$column++ if ( (($control_index + 1) % (int ($max_songs_per_page/2))) == 0 );
						#stop if we have done all inputs
						last if ++$control_index > $#songs;
					}
					# add start push button
					$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_push","song_start");
					$control->set_control_position( $layout_size->[0]-68 , 4+53*(($max_songs_per_page / 2)-1) );
					$control->set_control_minmax(0,1);
					$control->set_control_name("song_start");
					$control->set_control_color("green");
					$control->set_control_oscpath("/start");
					# add stop push button
					$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_push","song_stop");
					$control->set_control_position( $layout_size->[0]-68 , 4+53*(($max_songs_per_page / 2)-2) );
					$control->set_control_minmax(0,1);
					$control->set_control_name("song_stop");
					$control->set_control_color("red");
					$control->set_control_oscpath("/stop");
					# add zero push button
					$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_push","song_zero");
					$control->set_control_position( $layout_size->[0]-68 , 4+53*(($max_songs_per_page / 2)-3) );
					$control->set_control_minmax(0,1);
					$control->set_control_name("song_zero");
					$control->set_control_color("gray");
					$control->set_control_oscpath("/zero");
					# add bars/beat display
					$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_bbt","song_BBT");
					$control->set_control_name("song_BBT");
					$control->set_control_color("blue");
					$control->set_label_text("BBT");
					$control->set_label_outline("true");
					$control->set_control_position( $layout_size->[0]-80 , 4+53*(($max_songs_per_page / 2)-4) );
					$control->set_control_oscpath("/print/BBT");
					# add time display
					$control = $presets{$mixername}{$auxname}->add_control("Songs$pagenumber","small_time","song_time");
					$control->set_control_name("song_time");
					$control->set_control_color("blue");
					$control->set_label_text("Time");
					$control->set_label_outline("true");
					$control->set_control_position( $layout_size->[0]-80 , 4+53*(($max_songs_per_page / 2)-5) );
					$control->set_control_oscpath("/print/time");
				}
			}
		}

		#build preset for main out
		#-------------------------
		if ($mainout) {
			# create the hashref
			# $presets{$mixername}{$mainout} = TouchOSC->new($options); # TODO
		}

		elsif ($submixout) {
			# $presets{$mixername}{$submixout} = TouchOSC->new($options); # TODO
		}
	}

	return \%presets;
}

sub get_group_color {
	my $groupname = shift;
	return $colors[$default_color] if $groupname eq "";

	use feature 'state';
	state $groups = "";
	state $new = 0;

	my $index;
	my @table = split(',',$groups);

	if ( grep( /^$groupname$/, @table ) ) {
		#group existing, get its index as color index
		for my $nb (0..$#table) {
			$index = $nb if ($groupname eq $table[$nb]);
		}
	}
	else {
		#add groupname to groups list
		$groups .= "$groupname,";
		return $colors[$#table+1+$new];
		$new++;
	}
	
	return $colors[$index];
}

#	--- add something ---
#----------------------------------

sub add_page {
	my $touchosc = shift;
	my $pagename = shift;

	#encode page name
	my $page_title_base64 = Utils::encode_my_base64($pagename);
	chomp $page_title_base64;

	#this format is for pages with auto osc on page select # TODO deal with non auto pages
	$touchosc->{pages}{$pagename}{header} = "<tabpage name=\"$page_title_base64\" scalef=\"0.0\" scalet=\"1.0\" >";
	#create empty array for controls
	$touchosc->{pages}{$pagename}{controls} = ();

	bless $touchosc->{pages}{$pagename} , "TouchOSC_page";
}

sub add_control {
	my $touchosc = shift;
	my $pagename = shift;
	my $presetname = shift;
	my $controlname = shift;

	my $position;
	#verify if the control is a astrux_controls preset
	if (exists $astrux_controls->{$presetname}) {
		# print " | | |_adding control $controlname\n";

		#create a control from preset
		my %control = %{$astrux_controls->{$presetname}};
		
		#add preset to page
		$touchosc->{pages}{$pagename}{controls}{$controlname} = \%control;
	}
	else {
		# TODO create touchosc control from passed info
	}
	bless $touchosc->{pages}{$pagename}{controls}{$controlname} , "TouchOSC_control";

	return $touchosc->{pages}{$pagename}{controls}{$controlname};
}

###########################################################
#
#		 TOUCHOSC CONTROLS functions
#
###########################################################

#	--- controls create ---
#------------------------------

sub create_fader {
	my $width = shift;
	my $height = shift;
	my $color = shift || $default_color;

	my $fader = {
		name => "", #base64 encoded name
		x => "",
		y => "",
		w => $width, #object width from vertical layout view
		h => $height, #object height from vertical layout view
		color => $color,
		scalef => "", #minimum value
		scalet => "", #maximum value
		osc_cs => "", #base64 encoded osc path
		type => $type_fader[$default_type_fader], #faderh... or faderv ?
		response => $response[$default_control_response], #relative||absolute
		inverted => "false",
		centered => "false"
	};
	return $fader;
}

sub create_pot {
	my $width = shift;
	my $height = shift;
	my $color = shift || $default_color;

	my $pot = {
		name => "", #base64 encoded name
		x => "",
		y => "",
		w => $width, #object width from vertical layout view
		h => $height, #object height from vertical layout view
		color => $color,
		scalef => "", #minimum value
		scalet => "", #maximum value
		osc_cs => "", #base64 encoded osc path
		type => $type_rotary[$default_type_rotary], #rotaryh||rotaryv
		response => $response[$default_control_response], #relative||absolute
		inverted => "false",
		centered => "true",
		norollover => "true"
	};
	return $pot;
}

sub create_button {
	my $width = shift;
	my $height = shift;
	my $color = shift || $default_color;

	#toggle
	my $but = {
		name => "", #base64 encoded name
		x => "",
		y => "",
		w => $width, #object width from vertical layout view
		h => $height, #object height from vertical layout view
		color => $color,
		scalef => "", #minimum value
		scalet => "", #maximum value
		osc_cs => "", #base64 encoded osc path
		type => "toggle",
		local_off => "false"
	};
	return $but;
}

sub create_push {
	my $width = shift;
	my $height = shift;
	my $color = shift || $default_color;

	#toggle
	my $but = {
		name => "", #base64 encoded name
		x => "",
		y => "",
		w => $width, #object width from vertical layout view
		h => $height, #object height from vertical layout view
		color => $color,
		scalef => "", #minimum value
		scalet => "", #maximum value
		osc_cs => "", #base64 encoded osc path
		type => "push",
		local_off => "false"
	};
	return $but;
}

sub create_label {
	my $width = shift;
	my $height = shift;
	my $color = shift || $default_color;
	my $size = shift || $default_text_size;

	my $label = {
		name => "", #base64 encoded name
		x => "",
		y => "",
		w => $width, #object width from vertical layout view
		h => $height, #object height from vertical layout view
		color => $color,
		type => "labelv",
		text => "", #base64 encoded text
		size => $size,
		background => "false",
		outline => "false"
	};
	return $label;
}

#	--- controls SET values ---
#----------------------------------

package TouchOSC_control;

sub set_control_position {
	my $controlref = shift;
	my $xpos = shift;
	my $ypos = shift;
	$controlref->{y} = $xpos; # TODO it looks like touchosc takes xy inverted...cause vertical/horizontal ?
	$controlref->{x} = $ypos;
}
sub set_control_name {
	my $controlref = shift;
	my $name = shift;
	$controlref->{name} = Utils::encode_my_base64($name);
	chomp($controlref->{name});
}
sub set_control_color {
	my $controlref = shift;
	my $color = shift;
	$controlref->{color} = $color || $default_color;
	chomp($controlref->{color});
}
sub set_control_minmax {
	my $controlref = shift;
	my $min = shift;
	my $max = shift;
	$controlref->{scalef} = $min;
	$controlref->{scalet} = $max;
}
sub set_control_oscpath {
	my $controlref = shift;
	my $oscpath = shift;
	$controlref->{osc_cs} = Utils::encode_my_base64($oscpath);
	chomp($controlref->{osc_cs});
}
sub set_label_text {
       my $controlref = shift;
       my $text = shift;
       $controlref->{text} = Utils::encode_my_base64($text);
       chomp($controlref->{text});
}
sub set_label_outline {
       my $controlref = shift;
       my $text = shift;
       $controlref->{outline} = $text;
}

1;
