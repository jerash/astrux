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
my $layouts = { #(x,y)
	iphone => (480,320),
	ipad => (1024,768),
	iphone5 => (568,320),
	custom => (0,0)
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
	big_button => &create_button(80,80,"$colors[$default_color]"),
	track_label => &create_label(20,50,"$colors[$default_color]",13),
	aux_label => &create_label(20,50,"orange",13),
	monitor_label => &create_label(30,190,'gray',20),
	group_label => &create_label(30,155,"$colors[$default_color]",20)
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

	my $options = \%{$project->{touchosc}};

	foreach my $mixername (keys $project->{mixers}) {
		print " |_Project: creating TouchOSC presets for mixer $mixername\n";

		#get the touchosc presets
		my $touchoscpresets = TouchOSC::get_touchosc_presets($project->{mixers}{$mixername},$options);

		#save temporary xml file
		foreach my $presetname (keys %{$touchoscpresets}) {
			my $preset = $touchoscpresets->{$presetname};
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

# TODO use "groups" to define colours
# TODO if not exist plugin preset, make default

# --- monitor layout for iphone size ---
# { volume mix pages } { fx  pages        }
# { auxnam pagenam  M} { fxname pagenam   }
# { | | | | | | | | P} {  O  O  O  O    B }
# { | | | | | | | | |} {  O  O  O  O    G }
# { - - - - - - - - -} {  -  -  -  -      }

# --- main layout for ipad size ---
#	

sub get_touchosc_presets {
	my $mixer = shift;
	my $options = shift; #hashref containing layout options

	my %monitor_presets;
	my @inputnames;
	my @auxnames;
	my $mainout;
	my $submixout;
	
	# --- FIRST GET INPUTS, AUXES, and MAIN OUT ---
	if ($mixer->is_nonmixer) {
		@inputnames = $mixer->get_nonmixer_inputs_list; #main hardware in + submix ins
		@auxnames = $mixer->get_nonmixer_auxes_list; #will build preset for each aux (hardware out + fx send loop)
		$mainout = $mixer->get_nonmixer_mainout if $mixer->is_main; #will build preset for mainout (hardware out)
		$submixout = $mixer->get_nonmixer_submix_out if $mixer->is_submix; #will build preset for submixout (submix out)
	}
	elsif ($mixer->is_ecasound) {
		#TODO get ecasound inputs, auxes, mainout for touchosc
	} 
	else {
		warn "TouchOSC error: unknown mixer type\n";
		return;
	}

	# get layout dimensions
	my @size = $layouts->{$options->{layout_size}};
	my $max_channels_faders_per_page = int (($size[0] - 53) / 53);
	use POSIX qw(ceil);
	my $mix_pages_number = ceil( $#inputnames/$max_channels_faders_per_page );

	#build mix preset for each aux
	#------------------------------
	foreach my $auxname (@auxnames) {
		# create the hashref 
		$monitor_presets{$auxname} = TouchOSC->new($options);

		my $control;
		my $control_index = 0;
		#create the mix pages with volumes control
		for my $pagenumber (1..$mix_pages_number) {
			#add volume faders page(s)
			$monitor_presets{$auxname}->add_page("Mix$pagenumber");
			print " | |_adding page Mix$pagenumber for aux output $auxname\n";
	
			#for each input channel, add a volume control
			for my $nb (0..($max_channels_faders_per_page-1)) {
				#get inputname from list of inputs
				my $inputname = $inputnames[$control_index];
				#get input's mixer group
				my $color = &get_next_group_color($mixer->{channels}{$inputname}{group});
				# add input volume control fader
				$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","vol_fader","vol_$inputname");
				$control->set_control_position(2+53*($control_index-(($pagenumber-1)*$max_channels_faders_per_page)),20);
				$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
				$control->set_control_minmax(-60,6) if $mixer->is_ecasound;
				$control->set_control_name("vol_$inputname");
				$control->set_control_color($color);
				$control->set_control_oscpath("/$mixer->{engine}{name}/$inputname/aux_to/$auxname/vol");
				#add input label
				$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","track_label","label_$inputname");
				$control->set_control_name("label_$inputname");
				$control->set_control_color($color);
				$control->set_label_text("$inputname");
				$control->set_control_position(2+53*($control_index-(($pagenumber-1)*$max_channels_faders_per_page)),0);
				$control->set_control_oscpath("/dummy");
				#stop if we have done all inputs
				last if ++$control_index > $#inputnames;
			}
			#add aux master volume fader
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_fader","vol_$auxname");
			$control->set_control_position($layouts->{$monitor_presets{$auxname}{layout_size}}-53,20);
			$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
			$control->set_control_minmax(-60,6) if $mixer->is_ecasound;
			$control->set_control_name("vol_$auxname");
			$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/panvol/vol");
			#add aux master input label
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_label","label_$auxname");
			$control->set_control_name("label_$auxname");
			$control->set_label_text("Volume");
			$control->set_control_position($layouts->{$monitor_presets{$auxname}{layout_size}}-53,0);
			$control->set_control_oscpath("/dummy");
			#add aux master pan rotary
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","small_pot","pan_$auxname");
			$control->set_control_position($layouts->{$monitor_presets{$auxname}{layout_size}}-53,176);
			$control->set_control_minmax(0,1) if $mixer->is_nonmixer;
			$control->set_control_minmax(0,100) if $mixer->is_ecasound;
			$control->set_control_name("pan_$auxname");
			$control->set_control_color("orange");
			$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/panvol/pan");
			#add aux master mute label
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_label","mutel_$auxname");
			$control->set_control_name("mutel_$auxname");
			$control->set_label_text("mute");
			$control->set_control_position($layouts->{$monitor_presets{$auxname}{layout_size}}-53,243);
			$control->set_control_oscpath("/dummy");
			#add aux master mute button
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","small_button","mute_$auxname");
			$control->set_control_position($layouts->{$monitor_presets{$auxname}{layout_size}}-53,227);
			$control->set_control_minmax(0,1);
			$control->set_control_name("mute_$auxname");
			$control->set_control_color("orange");
			$control->set_control_oscpath("/$mixer->{engine}{name}/$auxname/mute");
			#add page label
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","monitor_label","label1_$auxname");
			$control->set_control_name("label1_$auxname");
			$control->set_label_text("$auxname");
			$control->set_control_position(0,230);
			$control->set_control_oscpath("/dummy");
			#add page name
			$control = $monitor_presets{$auxname}->add_control("Mix$pagenumber","group_label","label2_$auxname");
			$control->set_control_name("label2_$auxname");
			$control->set_label_text("Mix$pagenumber/$mix_pages_number");
			$control->set_control_position(190,230);
			$control->set_control_oscpath("/dummy");
		}
		#add fx inserts page(s) # TODO
	}
	#build preset for main out
	#-------------------------
	if ($mainout) {
		# create the hashref
		$monitor_presets{$mainout} = TouchOSC->new($options);
	}
	elsif ($submixout) {
		$monitor_presets{$submixout} = TouchOSC->new($options);
	}
	return \%monitor_presets;
}

sub get_next_group_color {
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
		return $colors[$#table+$new++];
	}
	
	return $colors[$index||$default_color];
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
	$controlref->{color} = $color;
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

1;