ASTRUX

A setup creation tool for live-oriented musicians
======
(under active development by Raphaël Mouneyres)

some features : 
  expandable audio mixer with channel strips, effects, submixes ... 
  personal monitoring buses with automatic touchosc presets generation
  support for external effects loop
  configurable midi patch with routing and filters
  audio/midi backing tracks
  save mixer states for each song (including personal monitoring mixes)
  ...etc

Linux based, using FLOSS only
  Audio engines : non-mixer, ecasound
  Midi engines : mididings, jpmidi, smfplayer
  Sampler engine : linuxsampler
  supported communication protocols : MIDI, OSC, TCP socket

To correctly build a project, you have to follow some rules :
- you follow the project folder structure
- you have correctly formatted INI files
- you have at least a project.ini file in the project folder
- you define audio mixers, with at least a 'main' mixer
- in each mixer, you define channels
- for each song you have a song.ini file

many error checks are done so the script will most probably die on missing or bad info.

Quick use
======
To generate files, cd into the project base folder and do : 
perl /pathto/generate.pl

To start the project, cd into the project base folder and do : 
perl /pathto/modules/Live.pl myproject.cfg

More info
======
All audio/midi parameters are accessible trough OSC and MIDI. A generated file is available as a reference.

Each audio output bus has independant controls, allowing personal monitoring mixes, and in-the-box foh mixing (individual inputs can also be routed to single hardware outputs for out-the-box mixing)
 
The whole astrux tool can be configured from the command-line without any GUI. It is based on standard INI files and a few scripts.A setup mode GUI exists as a frontend, generating the same necessary configuration files.

Also a live GUI exists for a user-friendly experience, but any OSC/MIDI/TCP remote can be used if the correct messages are passed/handled to/from astrux.

Audio players are based on ecasound. When a project containing multiple players on songs is started, ecasound will load all songs chainsetups in the background, but connect only one will be connected at a time. this allow for fast context switching from one song to another.

You can define replacement tracks to feed a strip with pre-recorded material. Just in case some real human is not here to do the job.

Project folder structure
======
```
base_folder
 |_audio           < FOLDER for audio mixers
 | |_main.ini      < the main mixer definition file
 | |_mixer2.ini    < another submix
 | |_players.ini   < ecasound mixer for audio backing tracks
 |
 |_hardware        < FOLDER for audio/midi hardware info
 | |_system.ini    < define which soundcard to use and more
 | |_hardware.csv  < generated file with ports list and aliases
 |
 |_midi            < FOLDER for midi related info
 | |_filter.py     < mididings file with midi filters and more
 | |_midipatch.ini < midi routing definitions mainly
 |
 |_project         < FOLDER with global project info
 | |_bridge.ini    < osc, midi, tcp configuration
 | |_project.ini   < engines activation, project files ...
 |
 |_songs           < FOLDER containing the songs necessary files
   |_song1.ini     < song info, players definitions
   |_song1         < song FOLDER containing the files for that song
     |_file1.wav   < an audio file
     |_file2.mid   < a midi file
```

INI files examples
======

project.ini example
```
# PROJECT Globals
#-------------------------------------

[globals]
name = Complete
version = 0.1
mixers_path = audio
songs_path = songs
output_path = files

[mixerfiles]
mixer1 = main.ini
mixer2 = drums.ini
mixer3 = players.ini

[songfiles]
song1 = song1.ini
song2 = song2.ini

# Ressources usage / services options
#-------------------------------------

[jack]
samplerate = 48000
clocksource = internal
buffer = 128
periods = 2
start = jackd -R -P89 -d alsa -d hw:DSP -p128 -n2 &

[netjack]
enable = 0
audioports = 2
midiports = 1

[plumbing]
enable = 1

[a2jmidid]
enable = 1

[midi_player]
backend = jpmidi
enable = 0
port = 2013

[linuxsampler]
enable = 0
presetfolder = sampler
port = 8888

# other
#-------------------------------------

[touchosc]
enable = 1
layout_size = iphone
layout_orientation = vertical
layout_mode = 0
```
single channel ecasound mixer ini file example
```
[mixer_globals]
type = main
engine = ecasound
name = main
eca_cfg_path = ecacfg
control = midi,tcp
midi_port = alsaseq,astrux:0
tcp_port = 2868

# INPUTS

[mic_1]
type = hardware_in
status = active
friendly_name = leader's mic
group = singers
channels = 1
connect_1 = system:capture_1
insert = eq4b,complight
can_be_backed = yes
```
single channel non-mixer ini file example
```
[mixer_globals]
type = main
name = main
engine = non-mixer
control = osc
osc_port = 8010
autoconnect = 1
noui = 1
addpregain = 0
addmeters = 0

#INPUTS

[mic_1]
type = hardware_in
status = active
friendly_name = micn1
group = mics
channels = 1
connect_1 = system:capture_1
insert = 2598
can_be_backed = yes
```

here's a bridge.ini example 
```
#creates an OSC server
[OSC]
enable = 1
ip = 192.168.0.15
inport = 8000
outport = 9000
sendback = 0

#creates TCP server (telnet/netcat)
[TCP]
enable = 1
port = 8989

#creates a prompt on local machine
[CLI]
enable = 0
```
song.ini example 
```
[song_globals]
name = song2
#this name here is the same as containing folder name
friendly_name = The second song
tempo = 80
autostart = 0

[players_slot_1]
type = audio_player
filename = monofile.wav
channels = 1

[players_slot_2]
type = audio_player
filename = stereofile.wav
channels = 2

[MIDI_01]
type = midi_player
filename = midifile1.mid
route_to = linuxsampler:in_1

[SAMPLER]
type = sampler
filename = drums.lscp
```

Goals
======

Setup :
1)astrux scans the computer for audio/midi capabilities
2)the user builds a project
  - add analog/digital audio inputs/outputs based on computer capabilities
  - add audio and midi players (synchronized backing tracks)
  - add metronome track
  - add sampler instruments
3)astrux is generating the audio/midi configurations and offers unified/standardized control over TCP/OSC/MIDI

Use:
1) start saved project
2) now play !

OPTIONS
--------
 - rehersal mode
  audio channel strips are editable (will restart mixers)
  midi filters/patch are editable (will restart midi bridge)
  players remain active after the end, so you can rewind to any position
 - live mode
  players are stopped once reaching the end
  fallback to a defined inter-song state possible
 - preload all sampler instruments on startup

Milestones
======

V0.1 (12/02/2014)
-----
*INPUTS mixer 
  strips with volume,eq,auxsends
*PLAYERS 
  with ecasound
*MIXERS
  with ecasound or non-mixer

V0.2
-----
MIDI/OSC/TCP bridge live control
optionally generated touchosc presets
*SAMPLER
  clic
  drums
*MIDIPLAY
  jpmidi v0.3

V0.3
-----
jpmidi with master mode (jack control tempo/meters), or klick
video player (xjadeo)
automate fx rack / plugin host
realtime cpu/memory check (trigger alarms)
replacement tracks

V0.4
----
preloading the next song is possible, for faster context switching
live cd/usb distribution creation

V0.5
------
midi editor (midish with jack synchro)
audio editor (nama)
dmx player (with jack synchro) 
  > probably using midi with http://qlc.sourceforge.net/index.shtml
  > or OSC .... https://github.com/mcallegari/qlcplus

MIXER ini file infos
======

#*************************************************************************
# INPUT/OUTPUT CHANNEL OPTIONS
#*************************************************************************
# [channel_name]
#     unique channel name, must not contain spaces
# status
#     active : channel will be created in mixer
#     inactive : channel is defined but is not added to project
# type 
#     hardware_in : connect from audio input hardware port
#     return : connect from audio input hardware port (related to a send_n)
#     submix : connect from another created submix output
#     player : connect from a player output
#     bus_hardware_out : connect to audio output hardware port as personal monitor mix
#     main_hardware_out : connect to audio output hardware port as mainout
#     send_hardware_out : connect to audio output hardware port as external fx loop
# group
#     name : channels within the same group number can be grouped with nonmixer
#            in touchosc preset, each group will have different fader color
# name
#     short name to be used within the system
#     lowercase only, no space character allowed, only _ special character
# friendly_name
#     name to be displayed, space character allowed
# channels
#     1..2 : defines number of audio channel (1=mono, 2=stereo, more is to be tested)
# hardware_intput_n
#     defines to which physical hardware port to connect
#     one line per defined channel
# insert
#     name of the effect chain to add on the channel
#     correspoding ecasound preset or LADSPA ID must exist for successful apply
#     multiple insert can be added. Separate with commas
# can_be_backed
#     yes/no : offer the option to replace the hardware audio input with a file
# send
#     for a channel of type return, specify the corresponding send channelname
# return
#     for a channel of type send, specify the corresponding return channelname
# mode
#     stereo : output channel as stereo (default, as internals are stereo)
#     mono : force mono output
#*************************************************************************
