#ASTRUX

A setup creation tool for live-oriented musicians
(under active development by Raphaël Mouneyres)

##Features
- expandable audio mixer with channel strips, effects, submixes ... 
- personal monitoring buses with automatic touchosc presets generation
- support for external effects loop
- configurable midi patch with routing and filters
- audio/midi backing tracks
- save mixer states for each song (including personal monitoring mixes)
- ...etc

Linux based, using FLOSS only

- Audio engines : non-mixer, ecasound
- Midi engines : mididings, jpmidi, smfplayer
- Sampler engine : linuxsampler
- supported communication protocols : MIDI, OSC, TCP socket

All audio/midi parameters are accessible trough OSC, MIDI and TCP commands. Memo files are available as a reference to accessible parameters after project generation.

Each audio output bus has independent controls, allowing personal monitoring mixes, and in-the-box foh mixing (individual inputs can also be routed to single hardware outputs for out-of-the-box mixing)
 
The whole astrux tool can be configured from the command-line without any GUI. It is based on standard INI files and a few scripts. A setup mode GUI exists as a frontend, generating the same necessary configuration files.

Also a live GUI exists for a user-friendly experience, but any OSC/MIDI/TCP remote can be used if the correct messages are passed/handled to/from astrux.

Audio players are based on ecasound. When a project containing multiple players on songs is started, ecasound will load all songs chainsetups in the background, but connect only one will be connected at a time. this allow for fast context switching from one song to another.

You can define replacement tracks to feed a strip with pre-recorded material. Just in case some real human is not here to do the job.

##Goals
###SETUP
- astrux scans the computer for audio/midi capabilities
- the user builds a project
- add analog/digital audio inputs/outputs based on computer capabilities
- add audio and midi players (synchronized backing tracks)
- add metronome track
- add sampler instruments
- astrux is generating the audio/midi configurations and offers unified/standardized control over TCP/OSC/MIDI

###USE
- start the saved project
- now play !

###Rehersal mode
- audio channel strips are editable (will restart mixers, audio gap inevitable)
- midi filters/patch are editable (will transparently restart midi bridge)
- players remain active after the end, so you can rewind to any position
###Live mode
- players are stopped once reaching the end of a song
- automaic fallback to a defined inter-song state possible
- preload all sampler instruments on startup

##Milestones

###V0.1 (12/02/2014)
- INPUTS mixer : strips with volume,eq,auxsends
- PLAYERS : with ecasound
- MIXERS : with ecasound or non-mixer

###V0.2 (currently running)
- MIDI/OSC/TCP bridge live control
- optionally generated touchosc presets
- Metronome : klick with timebase master mode and jack control
- SAMPLER : drums
- MIDI : jpmidi v0.35 player

###V0.3
- web frontend for inifiles generation
- midi patchbay editor
- video player (xjadeo)
- replacement tracks
- tracks meters in osc server

###V0.4
- automate fx rack / plugin host
- realtime cpu/memory check (trigger alarms)
- preloading the next song is possible, for faster context switching
- dmx player (with jack synchro), probably using midi with http://qlc.sourceforge.net/index.shtml, or OSC .... https://github.com/mcallegari/qlcplus

###V0.5
- midi editor (midish with jack synchro)
- audio editor (nama)
- live cd/usb distribution creation

##Project folder structure
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

##Quick use
To correctly build a project, you have to follow some rules :
- you follow the project folder structure
- you have correctly formatted INI files
- you have at least a project.ini file in the project folder
- you define audio mixers, with at least a 'main' mixer
- in each mixer, you define channels
- for each song you have a song.ini file

To generate files, cd into the project base folder and do : 
perl /pathto/generate.pl

To start the project, cd into the project base folder and do : 
perl /pathto/modules/Live.pl myproject.cfg

many error checks are done so the script will most probably die on missing or bad info.

##OSC server commands
- /ping
- /start
- /stop
- /zero
- /locate f|i [position in seconds]
- /save/dumper
- /save/project
- /save/state
- /save/all
- /status (do nothing)
- /song s [songname]
- /reload/state
- /reload/statefile
- /clic/start
- /clic/stop
- /clic/sound i [0..3]
- /clic/sound ss [filename1] [filename2]
- /clic/tempo f|i [tempo]
- /eval s [perl code]

##INI files examples

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

bridge.ini example 
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
Audio mixer ini file infos
```
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
# connect_n
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
# touchosc_pages
#     list of touchosc pages presets for a personal monitor output
#*************************************************************************
```