#!/bin/bash

if [[ $ASTRUXBACKEND == 0 ]]
 then
  echo -----------------------------------------------
  echo   SESSION INIT
  echo -----------------------------------------------
fi

#recuperation du numero de carte hardware >> inutile grâce à /dev/dsp
#LINE=`aplay -l | grep 'Hammerfall DSP'`
#echo $LINE
#HDSPNUMBER=`expr "$LINE" : 'card \([0-9]\)'`
#echo La carte HDSP a le numero $HDSPNUMBER

echo --Init Worldclock---------------------------------------------
#sudo amixer -c $HDSPNUMBER sset 'Sample Clock Source' 'AutoSync' | sed s/^/SYNCHRO:/

if [[ $ASTRUXBACKEND == 0 ]]
 then
   echo Synchro interne, frequence 48kHz
   amixer -D hw:DSP sset 'Sample Clock Source' 'Internal 48.0 kHz'
fi

echo --Init Jack---------------------------------------------

#verification si jack est deja lance
JACK_PID=$(pgrep jackd)
if [[ -n $JACK_PID ]]
 then
  if [[ $ASTRUXBACKEND == 0 ]]
   then
   echo SYSTEM: jack est deja en tache de fond
   echo SYSTEM: JACK_PID $JACK_PID 
  fi
 else 
   echo Lancement de jack
   #jackd -R -P89 -d alsa -d hw:DSP -p128 -n2 &
   source ~/jackstart
   sleep 2
fi

echo --jpmidi server---------------------------------------------

JPMIDI_PID=$(pgrep jpmidi)
if [[ -n $JPMIDI_PID ]]
 then
  if [[ $ASTRUXBACKEND == 0 ]]
   then
    echo SYSTEM: jpmidi est deja en tache de fond
    echo SYSTEM: JPMIDI_PID $JPMIDI_PID
  fi
 else
  echo lancement de jpmidi en mode serveur
  /usr/local/bin/jpmidi -s /home/seijitsu/astrux/0x.nosong/dummy.mid 2>&1 &
  sleep 1
  sendjpmidi "connect 2"
fi

echo --linuxsampler---------------------------------------------

LINUXSAMPLER_PID=$(pgrep linuxsampler)
if [[ -n $LINUXSAMPLER_PID ]]
 then
  if [[ $ASTRUXBACKEND == 0 ]]
   then
    echo SYSTEM: linuxsampler est deja en tache de fond
    echo LINUXSAMPLER_PID $LINUXSAMPLER_PID
  fi
 else
  echo Lancement de linuxsampler
  #linuxsampler 2>&1 &
  #sleep 2
fi

echo --Init Hdspmixer---------------------------------------------

#if pgrep hdspmixer > /dev/null
# then
#   echo SYSTEM:hdspmixer est deja en tache de fond
# else
#  (hdspmixer | sed s/^/HDSPMIXER: /) &
#fi

#custom script
#(hdspinit | sed s/^/HDSPINIT: /)
if [[ -n $HDSPINIT ]]
 then
  echo SYSTEM: Initializing HDSP card
  source ~/scripts/hdspinit
  export HDSPINIT=1
 else
  echo SYSTEM: HDSP card has already been initialized
fi

echo --mididings---------------------------------------------
echo TODO

echo --a2jmidi bridge----------------------------------------
echo TODO

echo --jack.plumbing----------------------------------------
JACKPLUMBING_PID=$(pgrep jack.plumbing)
if [[ -n $JACKPLUMBING_PID ]]
 then
  if [[ $ASTRUXBACKEND == 0 ]]
   then
    echo SYSTEM: jack.plumbing est deja en tache de fond
    echo JACKPLUMBING_PID $JACKPLUMBING_PID
  fi
 else
  echo Lancement de jack.plumbing
  jack.plumbing > /dev/null 2>&1 &
  #sleep 2
fi

export ASTRUXBACKEND=1
