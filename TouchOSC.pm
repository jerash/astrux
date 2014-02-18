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
my $layout_sizes = { #(x,y)
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
my $default_layout_size = 'iphone';
my $default_color = 0;
my $default_layout_orientation = 0;
my $default_layout_mode = 0;
my $default_response = 1;
my $default_type_fader = 0;
my $default_type_rotary = 0;
my $default_text_size = 13;

# controls definitions
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

	my $layout_size = $options->{layout_size} || $default_layout_size;
	my $layout_orientation = $options->{layout_orientation} || $default_layout_orientation;
	my $layout_mode = $options->{layout_mode} || $default_layout_mode;

	#verify if passed info is usable
	if (! exists $layout_sizes->{$layout_size} ) {
		warn "TouchOSC warning: could not find layout_size $layout_size. Fallback to default\n";
		$layout_size = $default_layout_size;
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

sub save_presets_files {
	my $monitor_presets = shift;

	foreach my $presetname (keys %{$monitor_presets}) {
		my $preset = $monitor_presets->{$presetname};
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

		#zip file
		system("zip -j ./$presetname.touchosc /tmp/index.xml");
		#todo delete temp file
	}
	# filename index.xml
	# zip to xxx.touchosc
}

###########################################################
#
#		 TOUCHOSC functions
#
###########################################################

# TODO use "groups" to define colours
# TODO if not exist plugin preset, make default

# --- monitor layout for iphone size ---
# { auxname page    m}
# { | | | | | | | | I}
# { - - - - - - - - -}
#	page 1..n 	
	# texts :
		# label w=190 h=30, x=0   y=15, textsize 20, textcolor red,  oscpath /dummy, text "monitor name"
		# label w=155 h=30, x=190 y=15, textsize 20, textcolor gray, oscpath /dummy, text "group name"
	# myaux tracks volume : 
		# fader w50 h200, x=2+53* y=60
		# label w50 h20,  x=2+53* y=260, textsize 13, oscpath /dummy
	# mymonitor volume : 
		# fader w=50 h=200, y=60  x=layout width - 53
		# label w=50 h=20,  y=260 x=layout width - 53, textsize uppercase 13, oscpath /dummy
	# mymonitor pan : 
		# small centered pot w=50 h=50, y=6 x=layout width - 53
	# global mute
		# togglebutton w=50 h=50, y=6 x=layout width - 2*53
		# label w=50 h=20, y=22 x=layout width - 2*53, textsize 13, oscpath /dummy
#	page n+1..
	# my fx params (equaliser,limiter)
# --- main ---
#	
sub get_touchosc_presets {
	my $mixer = shift;
	my $options = shift; #hashref containing layout options

	my %monitor_presets;
	my @inputs;
	my @auxes;
	my $mainout;
	my $submixout;
	
	# --- FIRST GET INPUTS, AUXES, and MAIN OUT ---
	if ($mixer->is_nonmixer) {
		@inputs = $mixer->get_nonmixer_inputs_list; #main hardware in + submix ins
		@auxes = $mixer->get_nonmixer_auxes_list; #will build preset for each aux (hardware out + fx send loop)
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
	my @size = $layout_sizes->{$options->{layout_size}};
	my $max_channels_faders = int (($size[0] - 53) / 53);
	print "max nb faders = $max_channels_faders\n" if $debug;

	#build preset for each aux
	#-------------------------
	foreach my $auxname (@auxes) {
		
		# create the hashref
		$monitor_presets{$auxname} = TouchOSC->new($options);

		my $pagenumber = 1;
		#add volume faders page(s)
		$monitor_presets{$auxname}->add_page("Mix$pagenumber");
		
		my $control_number = 0;
		#for each input channel, add a volume control
		foreach my $input (@inputs) {
			# add input volume control
			$monitor_presets{$auxname}->add_control("Mix$pagenumber","vol_fader","vol_$input");
				# set position
				my @position = (2+53*$control_number,20);
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$input"}->set_control_position(\@position);
				# add minmax
				my @minmax;
				@minmax = (0,1) if $mixer->is_nonmixer;
				@minmax = (-60,6) if $mixer->is_ecasound;
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$input"}->set_control_minmax(\@minmax);
				#name
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$input"}->set_control_name("vol_$input");
				#osc
				my $oscpath = "/$mixer->{engine}{name}/$input/aux_to/$auxname/vol";
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$input"}->set_control_oscpath($oscpath);

			#add input label
			$monitor_presets{$auxname}->add_control("Mix$pagenumber","track_label","track_$input");
				#name
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$input"}->set_control_name("track_$input");
				#set label text
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$input"}->set_label_text("$input");
				# set position
				@position = (2+53*$control_number,0);
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$input"}->set_control_position(\@position);
				#osc
				$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$input"}->set_control_oscpath("/dummy");

			# check max number of inputs faders (8 max per page on iphone layout)
			if (++$control_number >= $max_channels_faders) {
				#TODO add aux master volume / mute / pan
				$pagenumber++;
				$control_number = 0;
				$monitor_presets{$auxname}->add_page("Mix$pagenumber");
			}				
		}
		#add aux master volume
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_fader","vol_$auxname");
			# set position
			my @position = ($layout_sizes->{$monitor_presets{$auxname}{layout_size}}-53,20);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$auxname"}->set_control_position(\@position);
			# add minmax
			my @minmax;
			@minmax = (0,1) if $mixer->is_nonmixer;
			@minmax = (-60,6) if $mixer->is_ecasound;
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$auxname"}->set_control_minmax(\@minmax);
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$auxname"}->set_control_name("vol_$auxname");
			#osc
			my $oscpath = "/$mixer->{engine}{name}/$auxname/panvol/vol";
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"vol_$auxname"}->set_control_oscpath($oscpath);
		#add aux master input label
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_label","track_$auxname");
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$auxname"}->set_control_name("track_$auxname");
			#set label text
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$auxname"}->set_label_text("Volume");
			# set position
			@position = ($layout_sizes->{$monitor_presets{$auxname}{layout_size}}-53,0);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$auxname"}->set_control_position(\@position);
			#osc
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"track_$auxname"}->set_control_oscpath("/dummy");
		#add aux master pan
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","small_pot","pan_$auxname");
			# set position
			@position = ($layout_sizes->{$monitor_presets{$auxname}{layout_size}}-53,176);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"pan_$auxname"}->set_control_position(\@position);
			# add minmax
			@minmax;
			@minmax = (0,1) if $mixer->is_nonmixer;
			@minmax = (0,100) if $mixer->is_ecasound;
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"pan_$auxname"}->set_control_minmax(\@minmax);
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"pan_$auxname"}->set_control_name("pan_$auxname");
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"pan_$auxname"}->set_control_color("orange");
			#osc
			$oscpath = "/$mixer->{engine}{name}/$auxname/panvol/pan";
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"pan_$auxname"}->set_control_oscpath($oscpath);
		#add aux master mute
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","aux_label","mutel_$auxname");
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mutel_$auxname"}->set_control_name("mutel_$auxname");
			#set label text
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mutel_$auxname"}->set_label_text("mute");
			# set position
			@position = ($layout_sizes->{$monitor_presets{$auxname}{layout_size}}-53,243);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mutel_$auxname"}->set_control_position(\@position);
			#osc
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mutel_$auxname"}->set_control_oscpath("/dummy");
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","small_button","mute_$auxname");
			# set position
			@position = ($layout_sizes->{$monitor_presets{$auxname}{layout_size}}-53,227);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mute_$auxname"}->set_control_position(\@position);
			# add minmax
			@minmax;
			@minmax = (0,1);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mute_$auxname"}->set_control_minmax(\@minmax);
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mute_$auxname"}->set_control_name("mute_$auxname");
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mute_$auxname"}->set_control_color("orange");
			#osc
			$oscpath = "/$mixer->{engine}{name}/$auxname/mute";
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"mute_$auxname"}->set_control_oscpath($oscpath);

		#add page label
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","monitor_label","label1_$auxname");
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label1_$auxname"}->set_control_name("label1_$auxname");
			#set label text
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label1_$auxname"}->set_label_text("$auxname");
			# set position
			@position = (0,230);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label1_$auxname"}->set_control_position(\@position);
			#osc
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label1_$auxname"}->set_control_oscpath("/dummy");
		#add page name
		$monitor_presets{$auxname}->add_control("Mix$pagenumber","group_label","label2_$auxname");
			#name
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label2_$auxname"}->set_control_name("label2_$auxname");
			#set label text
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label2_$auxname"}->set_label_text("Mix$pagenumber");
			# set position
			@position = (190,230);
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label2_$auxname"}->set_control_position(\@position);
			#osc
			$monitor_presets{$auxname}{pages}{"Mix$pagenumber"}{controls}{"label2_$auxname"}->set_control_oscpath("/dummy");

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

#	--- add something ---
#----------------------------------

sub add_page {
	my $touchosc = shift;
	my $pagename = shift;

	print "   |_adding page $pagename\n";
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
		print "   | |_adding control $controlname\n";

		#create a control from preset
		my %control = %{$astrux_controls->{$presetname}};
		
		#add preset to page
		$touchosc->{pages}{$pagename}{controls}{$controlname} = \%control;
	}
	else {
		# TODO create touchosc control from passed info
	}
	bless $touchosc->{pages}{$pagename}{controls}{$controlname} , "TouchOSC_control";
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
		type => "faderh", #faderh... or faderv ?
		response => "relative", #relative||absolute
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
		type => "rotaryh", #rotaryh||rotaryv
		response => "absolute", #relative||absolute
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
	my $position = shift; #(x,y)
	$controlref->{y} = $position->[0]; # TODO it looks like touchosc takes xy inverted...cause vertical/horizontal ?
	$controlref->{x} = $position->[1];
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
	my $values = shift; #(min,max)	
	$controlref->{scalef} = $values->[0];
	$controlref->{scalet} = $values->[1];
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